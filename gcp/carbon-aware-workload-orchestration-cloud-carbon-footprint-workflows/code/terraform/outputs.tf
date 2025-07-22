# Project and network information outputs
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone for compute resources"
  value       = var.zone
}

output "vpc_network_name" {
  description = "Name of the VPC network created for carbon-aware workloads"
  value       = google_compute_network.carbon_aware_vpc.name
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.carbon_aware_vpc.self_link
}

output "subnet_name" {
  description = "Name of the subnet created for compute resources"
  value       = google_compute_subnetwork.carbon_aware_subnet.name
}

output "subnet_self_link" {
  description = "Self-link of the subnet"
  value       = google_compute_subnetwork.carbon_aware_subnet.self_link
}

# Service account outputs
output "carbon_footprint_service_account_email" {
  description = "Email of the service account for carbon footprint data operations"
  value       = google_service_account.carbon_footprint_sa.email
}

output "function_service_account_email" {
  description = "Email of the service account for Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "workflow_service_account_email" {
  description = "Email of the service account for Cloud Workflows"
  value       = google_service_account.workflow_sa.email
}

# BigQuery resource outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for carbon footprint data"
  value       = google_bigquery_dataset.carbon_footprint.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.carbon_footprint.location
}

output "hourly_carbon_intensity_view" {
  description = "Name of the BigQuery view for hourly carbon intensity analysis"
  value       = google_bigquery_table.hourly_carbon_intensity.table_id
}

output "optimal_scheduling_windows_view" {
  description = "Name of the BigQuery view for optimal scheduling recommendations"
  value       = google_bigquery_table.optimal_scheduling_windows.table_id
}

# Pub/Sub resource outputs
output "carbon_decisions_topic_name" {
  description = "Name of the Pub/Sub topic for carbon-aware scheduling decisions"
  value       = google_pubsub_topic.carbon_aware_decisions.name
}

output "carbon_decisions_subscription_name" {
  description = "Name of the Pub/Sub subscription for workflow consumption"
  value       = google_pubsub_subscription.carbon_aware_workflow_sub.name
}

output "workload_status_topic_name" {
  description = "Name of the Pub/Sub topic for workload execution status"
  value       = google_pubsub_topic.workload_execution_status.name
}

output "workload_status_subscription_name" {
  description = "Name of the Pub/Sub subscription for status monitoring"
  value       = google_pubsub_subscription.workload_status_monitoring.name
}

# Cloud Storage outputs
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

# Cloud Function outputs
output "carbon_aware_function_name" {
  description = "Name of the carbon-aware scheduling Cloud Function"
  value       = google_cloudfunctions_function.carbon_aware_scheduler.name
}

output "carbon_aware_function_url" {
  description = "HTTP trigger URL for the carbon-aware scheduling function"
  value       = google_cloudfunctions_function.carbon_aware_scheduler.https_trigger_url
}

output "carbon_aware_function_region" {
  description = "Region where the carbon-aware function is deployed"
  value       = google_cloudfunctions_function.carbon_aware_scheduler.region
}

output "carbon_aware_function_runtime" {
  description = "Runtime used by the carbon-aware scheduling function"
  value       = google_cloudfunctions_function.carbon_aware_scheduler.runtime
}

# Compute Engine outputs
output "instance_template_name" {
  description = "Name of the instance template for carbon-optimized workloads"
  value       = google_compute_instance_template.carbon_optimized.name
}

output "instance_template_self_link" {
  description = "Self-link of the instance template"
  value       = google_compute_instance_template.carbon_optimized.self_link
}

output "machine_type" {
  description = "Machine type used for carbon-optimized instances"
  value       = var.machine_type
}

output "preemptible_instances_enabled" {
  description = "Whether preemptible instances are enabled for cost optimization"
  value       = var.enable_preemptible_instances
}

# Cloud Workflows outputs
output "workflow_name" {
  description = "Name of the carbon-aware orchestration workflow"
  value       = google_workflows_workflow.carbon_aware_orchestration.name
}

output "workflow_region" {
  description = "Region where the workflow is deployed"
  value       = google_workflows_workflow.carbon_aware_orchestration.region
}

output "workflow_service_account" {
  description = "Service account used by the carbon-aware workflow"
  value       = google_workflows_workflow.carbon_aware_orchestration.service_account
}

# Cloud Scheduler outputs
output "daily_batch_scheduler_name" {
  description = "Name of the daily batch processing scheduler job"
  value       = google_cloud_scheduler_job.daily_batch_carbon_aware.name
}

output "weekly_analytics_scheduler_name" {
  description = "Name of the weekly analytics processing scheduler job"
  value       = google_cloud_scheduler_job.weekly_analytics_carbon_aware.name
}

# Configuration and settings outputs
output "max_delay_hours" {
  description = "Maximum delay hours configured for carbon-aware scheduling"
  value       = var.max_delay_hours
}

output "carbon_intensity_threshold" {
  description = "Carbon intensity threshold for scheduling decisions"
  value       = var.carbon_intensity_threshold
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Monitoring outputs (conditional based on monitoring enabled)
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled for carbon metrics"
  value       = var.enable_monitoring
}

output "carbon_emissions_metric_type" {
  description = "Metric type for carbon workload emissions (if monitoring enabled)"
  value       = var.enable_monitoring ? "custom.googleapis.com/carbon-workload-emissions" : null
}

output "workload_delay_metric_type" {
  description = "Metric type for workload delay hours (if monitoring enabled)"
  value       = var.enable_monitoring ? "custom.googleapis.com/workload-delay-hours" : null
}

output "alert_policy_names" {
  description = "Names of monitoring alert policies created"
  value       = var.enable_monitoring ? [google_monitoring_alert_policy.high_carbon_intensity[0].display_name] : []
}

output "dashboard_enabled" {
  description = "Whether monitoring dashboard is enabled"
  value       = var.enable_monitoring && var.monitoring_dashboard_enabled
}

# Security and network outputs
output "firewall_rules" {
  description = "Names of firewall rules created for the carbon-aware workload network"
  value = [
    google_compute_firewall.allow_ssh.name,
    google_compute_firewall.allow_internal.name
  ]
}

output "private_google_access_enabled" {
  description = "Whether private Google access is enabled for the subnet"
  value       = var.enable_private_google_access
}

output "vpc_flow_logs_enabled" {
  description = "Whether VPC flow logs are enabled"
  value       = var.enable_vpc_flow_logs
}

# Cost optimization outputs
output "boot_disk_size_gb" {
  description = "Boot disk size in GB for compute instances"
  value       = var.boot_disk_size
}

output "boot_disk_type" {
  description = "Boot disk type for compute instances"
  value       = var.boot_disk_type
}

output "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  value       = var.function_memory
}

output "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  value       = var.function_timeout
}

# Environment and naming outputs
output "environment" {
  description = "Environment name (dev, staging, prod)"
  value       = var.environment
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for resource uniqueness"
  value       = local.random_suffix
  sensitive   = false
}

# Data retention outputs
output "carbon_footprint_retention_days" {
  description = "Number of days carbon footprint data is retained in BigQuery"
  value       = var.carbon_footprint_retention_days
}

output "dataset_location" {
  description = "Location configured for BigQuery datasets"
  value       = var.dataset_location
}

# API enablement verification
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "compute.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# Quick start commands output
output "quick_start_commands" {
  description = "Commands to quickly test the carbon-aware orchestration system"
  value = {
    test_function = "curl -X POST '${google_cloudfunctions_function.carbon_aware_scheduler.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"workload_type\":\"test\",\"urgency\":\"normal\",\"region\":\"${var.region}\"}'"
    
    trigger_workflow = "gcloud workflows execute ${google_workflows_workflow.carbon_aware_orchestration.name} --data='{\"workload_id\":\"test-${local.random_suffix}\",\"workload_type\":\"test\",\"urgency\":\"normal\",\"region\":\"${var.region}\"}' --location=${var.region}"
    
    view_logs = "gcloud logging read 'resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions_function.carbon_aware_scheduler.name}' --limit=10"
    
    check_pubsub = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.carbon_aware_workflow_sub.name} --limit=5 --auto-ack"
    
    view_bigquery_data = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.carbon_footprint.dataset_id}.hourly_carbon_intensity` LIMIT 10'"
  }
}

# Cost estimation guidance
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for carbon-aware orchestration resources (USD)"
  value = {
    note = "Costs vary based on usage patterns and regions"
    bigquery_storage = "$0.02 per GB per month"
    cloud_functions = "$0.40 per million invocations + $0.0000025 per GB-second"
    pubsub = "$0.40 per million operations"
    workflows = "$0.01 per 1000 internal steps"
    compute_engine = "Varies by machine type and usage (e2-standard-2: ~$50/month if running 24/7)"
    cloud_scheduler = "$0.10 per job per month"
    monitoring = "First 150MB of logs free, then $0.50 per GB"
    estimated_total = "$15-25 for recipe testing, $100-500 for production workloads"
  }
}