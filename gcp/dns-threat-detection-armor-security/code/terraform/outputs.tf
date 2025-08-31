# Outputs for GCP DNS threat detection infrastructure

output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
  sensitive   = false
}

# DNS Infrastructure Outputs
output "dns_policy_name" {
  description = "Name of the DNS policy with logging enabled"
  value       = var.enable_dns_logging ? google_dns_policy.security_policy[0].name : null
}

output "dns_zone_name" {
  description = "Name of the DNS managed zone for security monitoring"
  value       = google_dns_managed_zone.security_zone.name
}

output "dns_zone_dns_name" {
  description = "DNS name of the managed zone"
  value       = google_dns_managed_zone.security_zone.dns_name
}

output "dns_zone_name_servers" {
  description = "Name servers for the DNS managed zone"
  value       = google_dns_managed_zone.security_zone.name_servers
}

# Cloud Armor Security Outputs
output "cloud_armor_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = var.enable_cloud_armor ? google_compute_security_policy.dns_protection[0].name : null
}

output "cloud_armor_policy_id" {
  description = "ID of the Cloud Armor security policy"
  value       = var.enable_cloud_armor ? google_compute_security_policy.dns_protection[0].id : null
}

output "cloud_armor_policy_self_link" {
  description = "Self link of the Cloud Armor security policy"
  value       = var.enable_cloud_armor ? google_compute_security_policy.dns_protection[0].self_link : null
}

# Pub/Sub Infrastructure Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for security alerts"
  value       = google_pubsub_topic.security_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.security_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for alert processing"
  value       = google_pubsub_subscription.alert_processor.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.alert_processor.id
}

# Cloud Function Outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function for automated response"
  value       = var.enable_automated_response ? google_cloudfunctions_function.dns_security_processor[0].name : null
}

output "cloud_function_trigger" {
  description = "Trigger configuration for the Cloud Function"
  value       = var.enable_automated_response ? google_cloudfunctions_function.dns_security_processor[0].event_trigger[0].event_type : null
}

output "cloud_function_service_account" {
  description = "Service account email for the Cloud Function"
  value       = var.enable_automated_response ? google_service_account.function_sa[0].email : null
}

output "cloud_function_source_bucket" {
  description = "Cloud Storage bucket containing function source code"
  value       = var.enable_automated_response ? google_storage_bucket.function_source[0].name : null
}

# Security Command Center Outputs
output "scc_notification_config_name" {
  description = "Name of the Security Command Center notification configuration"
  value       = var.enable_security_center_premium ? google_scc_notification_config.dns_threat_export[0].config_id : null
}

output "scc_notification_config_id" {
  description = "Full resource ID of the Security Command Center notification configuration"
  value       = var.enable_security_center_premium ? google_scc_notification_config.dns_threat_export[0].name : null
}

# Monitoring Outputs
output "log_metric_name" {
  description = "Name of the log-based metric for DNS malware queries"
  value       = google_logging_metric.dns_malware_queries.name
}

output "alert_policy_name" {
  description = "Name of the monitoring alert policy for DNS threats"
  value       = google_monitoring_alert_policy.dns_threat_alert.display_name
}

output "alert_policy_id" {
  description = "ID of the monitoring alert policy"
  value       = google_monitoring_alert_policy.dns_threat_alert.name
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if configured)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email[0].name : null
}

# API Services Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Network Outputs
output "default_network_name" {
  description = "Name of the default VPC network"
  value       = data.google_compute_network.default.name
}

output "default_network_self_link" {
  description = "Self link of the default VPC network"
  value       = data.google_compute_network.default.self_link
}

# Security Configuration Summary
output "security_configuration_summary" {
  description = "Summary of security configuration status"
  value = {
    dns_logging_enabled         = var.enable_dns_logging
    cloud_armor_enabled         = var.enable_cloud_armor
    automated_response_enabled  = var.enable_automated_response
    security_center_premium     = var.enable_security_center_premium
    rate_limit_threshold        = var.rate_limit_threshold
    blocked_countries          = var.high_risk_countries
    alert_threshold            = var.monitoring_alert_threshold
    notification_configured    = var.notification_email != ""
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    deployment_timestamp = timestamp()
    terraform_version    = ">= 1.6"
    google_provider_version = "~> 6.0"
    resource_labels      = local.common_labels
    cost_estimate        = "Estimated monthly cost: $50-150 USD (varies by usage)"
  }
}

# Operational URLs and Links
output "operational_links" {
  description = "Useful links for managing and monitoring the deployment"
  value = {
    security_command_center_url = "https://console.cloud.google.com/security/command-center"
    cloud_armor_policies_url    = "https://console.cloud.google.com/net-security/securitypolicies/list"
    cloud_functions_url         = "https://console.cloud.google.com/functions/list"
    cloud_monitoring_url        = "https://console.cloud.google.com/monitoring"
    cloud_logging_url          = "https://console.cloud.google.com/logs"
    dns_zones_url              = "https://console.cloud.google.com/net-services/dns/zones"
    pubsub_topics_url          = "https://console.cloud.google.com/cloudpubsub/topic/list"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_dns_policy = var.enable_dns_logging ? "gcloud dns policies describe ${google_dns_policy.security_policy[0].name}" : "DNS logging disabled"
    check_security_policy = var.enable_cloud_armor ? "gcloud compute security-policies describe ${google_compute_security_policy.dns_protection[0].name}" : "Cloud Armor disabled"
    check_function_logs = var.enable_automated_response ? "gcloud functions logs read ${google_cloudfunctions_function.dns_security_processor[0].name} --limit=10" : "Automated response disabled"
    test_pubsub_flow = "gcloud pubsub topics publish ${google_pubsub_topic.security_alerts.name} --message='{\"test\":\"message\"}'"
    check_log_metric = "gcloud logging metrics describe ${google_logging_metric.dns_malware_queries.name}"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value = {
    destroy_terraform = "terraform destroy -auto-approve"
    delete_project = "gcloud projects delete ${var.project_id} --quiet"
    warning = "⚠️  These commands will permanently delete resources. Use with extreme caution!"
  }
}