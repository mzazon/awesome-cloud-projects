# Outputs for GCP Domain and Certificate Lifecycle Management
# Recipe: Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager

# DNS Zone Information
output "dns_zone_name" {
  description = "Name of the created DNS zone"
  value       = google_dns_managed_zone.automation_zone.name
}

output "dns_zone_id" {
  description = "ID of the created DNS zone"
  value       = google_dns_managed_zone.automation_zone.id
}

output "dns_zone_nameservers" {
  description = "Nameservers for the DNS zone (configure these with your domain registrar)"
  value       = google_dns_managed_zone.automation_zone.name_servers
}

output "domain_name" {
  description = "Primary domain name being managed"
  value       = var.domain_name
}

# Certificate Information
output "certificate_name" {
  description = "Name of the managed SSL certificate"
  value       = google_certificate_manager_certificate.ssl_certificate.name
}

output "certificate_id" {
  description = "ID of the managed SSL certificate"
  value       = google_certificate_manager_certificate.ssl_certificate.id
}

output "certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = local.all_certificate_domains
}

output "certificate_map_name" {
  description = "Name of the certificate map"
  value       = google_certificate_manager_certificate_map.cert_map.name
}

output "certificate_map_id" {
  description = "ID of the certificate map"
  value       = google_certificate_manager_certificate_map.cert_map.id
}

# Service Account Information
output "service_account_email" {
  description = "Email of the service account used for automation"
  value       = google_service_account.cert_automation.email
}

output "service_account_id" {
  description = "ID of the service account used for automation"
  value       = google_service_account.cert_automation.id
}

# Cloud Functions Information
output "cert_monitoring_function_name" {
  description = "Name of the certificate monitoring Cloud Function"
  value       = google_cloudfunctions_function.cert_monitoring.name
}

output "cert_monitoring_function_url" {
  description = "HTTPS trigger URL for the certificate monitoring function"
  value       = google_cloudfunctions_function.cert_monitoring.https_trigger_url
  sensitive   = true
}

output "dns_update_function_name" {
  description = "Name of the DNS update Cloud Function"
  value       = google_cloudfunctions_function.dns_update.name
}

output "dns_update_function_url" {
  description = "HTTPS trigger URL for the DNS update function"
  value       = google_cloudfunctions_function.dns_update.https_trigger_url
  sensitive   = true
}

# Cloud Scheduler Information
output "cert_monitoring_scheduler_job" {
  description = "Name of the certificate monitoring scheduler job"
  value       = var.enable_monitoring ? google_cloud_scheduler_job.cert_monitoring[0].name : null
}

output "daily_audit_scheduler_job" {
  description = "Name of the daily audit scheduler job"
  value       = var.enable_monitoring ? google_cloud_scheduler_job.daily_audit[0].name : null
}

output "monitoring_schedule" {
  description = "Cron schedule for certificate monitoring"
  value       = var.monitoring_schedule
}

output "daily_audit_schedule" {
  description = "Cron schedule for daily certificate audit"
  value       = var.daily_audit_schedule
}

# Load Balancer Information (if created)
output "load_balancer_ip" {
  description = "IP address of the load balancer (if created)"
  value       = var.create_load_balancer ? google_compute_global_forwarding_rule.demo_https_rule[0].ip_address : null
}

output "load_balancer_url" {
  description = "HTTPS URL for the load balancer (if created)"
  value       = var.create_load_balancer ? "https://${var.domain_name}" : null
}

output "backend_service_name" {
  description = "Name of the backend service (if created)"
  value       = var.create_load_balancer ? google_compute_backend_service.demo_backend[0].name : null
}

output "url_map_name" {
  description = "Name of the URL map (if created)"
  value       = var.create_load_balancer ? google_compute_url_map.demo_url_map[0].name : null
}

output "https_proxy_name" {
  description = "Name of the HTTPS proxy (if created)"
  value       = var.create_load_balancer ? google_compute_target_https_proxy.demo_https_proxy[0].name : null
}

# Cloud Armor Information (if enabled)
output "cloud_armor_policy_name" {
  description = "Name of the Cloud Armor security policy (if enabled)"
  value       = var.enable_cloud_armor && var.create_load_balancer ? google_compute_security_policy.cloud_armor_policy[0].name : null
}

# DNS Records Information
output "a_record_name" {
  description = "Name of the A record pointing to the load balancer"
  value       = var.create_load_balancer ? google_dns_record_set.a_record[0].name : null
}

output "www_cname_record" {
  description = "CNAME record for www subdomain (if enabled)"
  value       = var.enable_www_subdomain && var.create_load_balancer ? google_dns_record_set.www_cname[0].name : null
}

# Project and Region Information
output "project_id" {
  description = "GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "GCP zone where zonal resources were created"
  value       = var.zone
}

# Resource Names and Identifiers
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Function Testing Commands
output "test_certificate_monitoring" {
  description = "Command to manually test certificate monitoring function"
  value       = "curl -X GET '${google_cloudfunctions_function.cert_monitoring.https_trigger_url}'"
}

output "test_dns_update" {
  description = "Example command to test DNS update function"
  value = jsonencode({
    command = "curl -X POST '${google_cloudfunctions_function.dns_update.https_trigger_url}'"
    headers = "Content-Type: application/json"
    body = {
      zone_name    = google_dns_managed_zone.automation_zone.name
      record_name  = "test.${var.domain_name}."
      record_type  = "A"
      record_data  = "1.2.3.4"
      ttl          = 300
    }
  })
}

# Important Setup Instructions
output "setup_instructions" {
  description = "Important setup instructions for completing the configuration"
  value = {
    nameserver_configuration = "Configure these nameservers with your domain registrar: ${join(", ", google_dns_managed_zone.automation_zone.name_servers)}"
    certificate_validation   = "Certificate will automatically validate after DNS delegation is complete"
    monitoring_access        = "Certificate monitoring function: ${google_cloudfunctions_function.cert_monitoring.https_trigger_url}"
    dns_management          = "DNS update function: ${google_cloudfunctions_function.dns_update.https_trigger_url}"
    load_balancer_ready     = var.create_load_balancer ? "Load balancer will be accessible at https://${var.domain_name} after certificate validation" : "Load balancer not created (set create_load_balancer = true to enable)"
  }
}

# Cost Monitoring Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    dns_zone              = "$0.50 per zone + $0.40 per million queries"
    certificate_manager   = "Free for Google-managed certificates"
    cloud_functions      = "$0.40 per million requests + $0.0000025 per GB-second"
    cloud_scheduler      = "$0.10 per job per month"
    load_balancer        = var.create_load_balancer ? "$18 per month + $0.008 per GB processed" : "Not applicable"
    cloud_armor          = var.enable_cloud_armor ? "$5 per policy per month + $1 per million requests" : "Not applicable"
    estimated_total      = "$5-15 per month for typical usage"
  }
}