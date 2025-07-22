# ==============================================================================
# TERRAFORM OUTPUTS FOR NETWORK PERFORMANCE OPTIMIZATION
# ==============================================================================
# This file defines all output values for the network performance optimization
# solution, providing essential information for verification, integration, and
# operational management of the deployed infrastructure.
# ==============================================================================

# ------------------------------------------------------------------------------
# PROJECT AND IDENTITY OUTPUTS
# ------------------------------------------------------------------------------

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "deployment_id" {
  description = "Unique deployment identifier for resource tracking"
  value       = random_id.suffix.hex
}

output "deployment_region" {
  description = "Primary region where network optimization resources are deployed"
  value       = var.region
}

output "secondary_region" {
  description = "Secondary region for multi-region network testing"
  value       = var.secondary_region
}

# ------------------------------------------------------------------------------
# NETWORK INFRASTRUCTURE OUTPUTS
# ------------------------------------------------------------------------------

output "vpc_network_id" {
  description = "Full resource ID of the network optimization VPC"
  value       = google_compute_network.network_optimization_vpc.id
}

output "vpc_network_name" {
  description = "Name of the network optimization VPC"
  value       = google_compute_network.network_optimization_vpc.name
}

output "vpc_network_self_link" {
  description = "Self-link of the network optimization VPC for reference in other resources"
  value       = google_compute_network.network_optimization_vpc.self_link
}

output "primary_subnet_id" {
  description = "Full resource ID of the primary subnet"
  value       = google_compute_subnetwork.primary_subnet.id
}

output "primary_subnet_cidr" {
  description = "CIDR block of the primary subnet"
  value       = google_compute_subnetwork.primary_subnet.ip_cidr_range
}

output "secondary_subnet_id" {
  description = "Full resource ID of the secondary subnet"
  value       = google_compute_subnetwork.secondary_subnet.id
}

output "secondary_subnet_cidr" {
  description = "CIDR block of the secondary subnet"
  value       = google_compute_subnetwork.secondary_subnet.ip_cidr_range
}

# ------------------------------------------------------------------------------
# CLOUD WAN AND NETWORK CONNECTIVITY OUTPUTS
# ------------------------------------------------------------------------------

output "network_connectivity_hub_id" {
  description = "Resource ID of the Network Connectivity Hub"
  value       = google_network_connectivity_hub.network_optimization_hub.id
}

output "network_connectivity_hub_name" {
  description = "Name of the Network Connectivity Hub"
  value       = google_network_connectivity_hub.network_optimization_hub.name
}

output "network_connectivity_hub_uri" {
  description = "URI of the Network Connectivity Hub for external references"
  value       = google_network_connectivity_hub.network_optimization_hub.id
}

# ------------------------------------------------------------------------------
# COMPUTE INSTANCE OUTPUTS
# ------------------------------------------------------------------------------

output "primary_test_instance_id" {
  description = "Resource ID of the primary test instance"
  value       = google_compute_instance.primary_test_instance.id
}

output "primary_test_instance_internal_ip" {
  description = "Internal IP address of the primary test instance"
  value       = google_compute_instance.primary_test_instance.network_interface[0].network_ip
}

output "primary_test_instance_zone" {
  description = "Zone where the primary test instance is deployed"
  value       = google_compute_instance.primary_test_instance.zone
}

output "secondary_test_instance_id" {
  description = "Resource ID of the secondary test instance"
  value       = google_compute_instance.secondary_test_instance.id
}

output "secondary_test_instance_internal_ip" {
  description = "Internal IP address of the secondary test instance"
  value       = google_compute_instance.secondary_test_instance.network_interface[0].network_ip
}

output "secondary_test_instance_zone" {
  description = "Zone where the secondary test instance is deployed"
  value       = google_compute_instance.secondary_test_instance.zone
}

# ------------------------------------------------------------------------------
# NETWORK INTELLIGENCE CENTER OUTPUTS
# ------------------------------------------------------------------------------

output "regional_connectivity_test_id" {
  description = "Resource ID of the regional connectivity test"
  value       = google_network_management_connectivity_test.regional_connectivity_test.id
}

output "regional_connectivity_test_name" {
  description = "Name of the regional connectivity test"
  value       = google_network_management_connectivity_test.regional_connectivity_test.name
}

output "external_connectivity_test_id" {
  description = "Resource ID of the external connectivity test"
  value       = google_network_management_connectivity_test.external_connectivity_test.id
}

output "external_connectivity_test_name" {
  description = "Name of the external connectivity test"
  value       = google_network_management_connectivity_test.external_connectivity_test.name
}

# ------------------------------------------------------------------------------
# PUB/SUB MESSAGING OUTPUTS
# ------------------------------------------------------------------------------

output "network_events_topic_id" {
  description = "Resource ID of the network optimization events Pub/Sub topic"
  value       = google_pubsub_topic.network_optimization_events.id
}

output "network_events_topic_name" {
  description = "Name of the network optimization events Pub/Sub topic"
  value       = google_pubsub_topic.network_optimization_events.name
}

output "network_events_subscription_id" {
  description = "Resource ID of the network events subscription"
  value       = google_pubsub_subscription.network_events_subscription.id
}

output "network_events_subscription_name" {
  description = "Name of the network events subscription"
  value       = google_pubsub_subscription.network_events_subscription.name
}

output "dead_letter_topic_id" {
  description = "Resource ID of the dead letter queue topic"
  value       = google_pubsub_topic.dead_letter_queue.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.dead_letter_queue.name
}

# ------------------------------------------------------------------------------
# CLOUD FUNCTION OUTPUTS
# ------------------------------------------------------------------------------

output "network_optimization_function_id" {
  description = "Resource ID of the network optimization Cloud Function"
  value       = google_cloudfunctions2_function.network_optimization_processor.id
}

output "network_optimization_function_name" {
  description = "Name of the network optimization Cloud Function"
  value       = google_cloudfunctions2_function.network_optimization_processor.name
}

output "network_optimization_function_url" {
  description = "HTTP trigger URL of the network optimization function (if HTTP trigger is configured)"
  value       = google_cloudfunctions2_function.network_optimization_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.network_optimization_sa.email
}

# ------------------------------------------------------------------------------
# STORAGE OUTPUTS
# ------------------------------------------------------------------------------

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.url
}

# ------------------------------------------------------------------------------
# MONITORING AND ALERTING OUTPUTS
# ------------------------------------------------------------------------------

output "monitoring_dashboard_url" {
  description = "URL to access the network optimization monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.network_optimization_dashboard.id)}?project=${var.project_id}"
}

output "alert_policy_id" {
  description = "Resource ID of the network performance alert policy"
  value       = google_monitoring_alert_policy.network_performance_alert.id
}

output "alert_policy_name" {
  description = "Name of the network performance alert policy"
  value       = google_monitoring_alert_policy.network_performance_alert.display_name
}

output "notification_channel_id" {
  description = "Resource ID of the email notification channel"
  value       = google_monitoring_notification_channel.email_notification.id
}

output "notification_email" {
  description = "Email address configured for network optimization alerts"
  value       = var.notification_email
  sensitive   = true
}

# ------------------------------------------------------------------------------
# CLOUD SCHEDULER OUTPUTS
# ------------------------------------------------------------------------------

output "periodic_analysis_job_id" {
  description = "Resource ID of the periodic network analysis scheduler job"
  value       = google_cloud_scheduler_job.periodic_network_analysis.id
}

output "periodic_analysis_job_name" {
  description = "Name of the periodic network analysis scheduler job"
  value       = google_cloud_scheduler_job.periodic_network_analysis.name
}

output "daily_report_job_id" {
  description = "Resource ID of the daily network report scheduler job"
  value       = google_cloud_scheduler_job.daily_network_report.id
}

output "daily_report_job_name" {
  description = "Name of the daily network report scheduler job"
  value       = google_cloud_scheduler_job.daily_network_report.name
}

# ------------------------------------------------------------------------------
# OPERATIONS AND MANAGEMENT OUTPUTS
# ------------------------------------------------------------------------------

output "network_intelligence_center_url" {
  description = "URL to access Network Intelligence Center in the Google Cloud Console"
  value       = "https://console.cloud.google.com/net-intelligence?project=${var.project_id}"
}

output "connectivity_tests_url" {
  description = "URL to view connectivity test results in the Google Cloud Console"
  value       = "https://console.cloud.google.com/net-intelligence/connectivity/tests?project=${var.project_id}"
}

output "vpc_flow_logs_url" {
  description = "URL to access VPC Flow Logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22gce_subnetwork%22?project=${var.project_id}"
}

output "cloud_functions_url" {
  description = "URL to manage Cloud Functions in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

# ------------------------------------------------------------------------------
# COST AND RESOURCE TRACKING OUTPUTS
# ------------------------------------------------------------------------------

output "resource_labels" {
  description = "Common labels applied to all resources for cost tracking and organization"
  value = {
    environment = var.environment
    created_by  = var.created_by
    purpose     = "network-optimization"
    deployment  = random_id.suffix.hex
  }
}

output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs for major components"
  value = {
    note = "Costs vary based on usage patterns, data transfer volumes, and monitoring frequency"
    vpc_flow_logs = "Charged based on log volume generated (sampling rate: ${var.vpc_flow_logs_sampling * 100}%)"
    cloud_functions = "Charged per invocation and compute time"
    connectivity_tests = "First 100 tests per month are free, then charged per test"
    monitoring = "Some metrics included in free tier, additional charges for custom metrics"
    storage = "Standard storage rates apply for function source code and logs"
  }
}

# ------------------------------------------------------------------------------
# VALIDATION AND HEALTH CHECK OUTPUTS
# ------------------------------------------------------------------------------

output "deployment_validation_commands" {
  description = "Commands to validate the deployment and test network optimization functionality"
  value = {
    check_connectivity_tests = "gcloud network-management connectivity-tests list --project=${var.project_id}"
    view_vpc_flow_logs = "gcloud logging read 'resource.type=\"gce_subnetwork\"' --limit=10 --project=${var.project_id}"
    test_function_trigger = "gcloud pubsub topics publish ${google_pubsub_topic.network_optimization_events.name} --message='{\"test\":\"true\"}' --project=${var.project_id}"
    view_monitoring_dashboard = "echo 'Open ${google_monitoring_dashboard.network_optimization_dashboard.id} in Cloud Console'"
    check_scheduler_jobs = "gcloud scheduler jobs list --project=${var.project_id}"
  }
}

output "troubleshooting_info" {
  description = "Useful information for troubleshooting and monitoring the network optimization solution"
  value = {
    function_logs_command = "gcloud functions logs read ${google_cloudfunctions2_function.network_optimization_processor.name} --region=${var.region} --limit=20"
    pubsub_metrics_filter = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${google_pubsub_topic.network_optimization_events.name}\""
    connectivity_test_results = "Results available in Network Intelligence Center > Connectivity Tests"
    alert_policy_status = "Monitor alert policy status in Cloud Monitoring > Alerting"
    vpc_flow_analysis = "Use Network Intelligence Center > Flow Analyzer for traffic pattern analysis"
  }
}

# ------------------------------------------------------------------------------
# INTEGRATION OUTPUTS
# ------------------------------------------------------------------------------

output "terraform_state_info" {
  description = "Information about the Terraform deployment for integration with other systems"
  value = {
    deployment_timestamp = timestamp()
    terraform_version = "~> 1.0"
    google_provider_version = "~> 6.0"
    deployment_region = var.region
    secondary_region = var.secondary_region
  }
}