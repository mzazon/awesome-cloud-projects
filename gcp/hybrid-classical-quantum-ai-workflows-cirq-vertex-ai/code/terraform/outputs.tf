# Output Values for Hybrid Quantum-Classical AI Workflows
# These outputs provide important information about the deployed infrastructure

# Project and Region Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources were deployed"
  value       = var.zone
}

output "resource_suffix" {
  description = "The unique suffix used for resource naming"
  value       = local.suffix
}

# Networking Outputs
output "vpc_network_name" {
  description = "Name of the VPC network created for quantum computing workloads"
  value       = google_compute_network.quantum_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.quantum_vpc.id
}

output "subnet_name" {
  description = "Name of the subnet created for quantum computing resources"
  value       = google_compute_subnetwork.quantum_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.quantum_subnet.ip_cidr_range
}

# Storage Outputs
output "data_bucket_name" {
  description = "Name of the Cloud Storage bucket for quantum computing data and results"
  value       = google_storage_bucket.quantum_data.name
}

output "data_bucket_url" {
  description = "URL of the Cloud Storage bucket for data"
  value       = google_storage_bucket.quantum_data.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for Cloud Functions source code"
  value       = google_storage_bucket.function_source.name
}

# Vertex AI Outputs
output "vertex_ai_workbench_name" {
  description = "Name of the Vertex AI Workbench instance for quantum development"
  value       = google_notebooks_instance.quantum_workbench.name
}

output "vertex_ai_workbench_url" {
  description = "URL to access the Vertex AI Workbench instance"
  value       = "https://console.cloud.google.com/vertex-ai/workbench/instances/${var.zone}/${google_notebooks_instance.quantum_workbench.name}?project=${var.project_id}"
}

output "vertex_ai_service_account" {
  description = "Email of the service account used by Vertex AI Workbench"
  value       = google_service_account.vertex_ai_sa.email
}

# Cloud Functions Outputs
output "quantum_orchestrator_name" {
  description = "Name of the Cloud Function for quantum workflow orchestration"
  value       = google_cloudfunctions_function.quantum_orchestrator.name
}

output "quantum_orchestrator_url" {
  description = "HTTP trigger URL for the quantum orchestration function"
  value       = google_cloudfunctions_function.quantum_orchestrator.https_trigger_url
  sensitive   = true
}

output "quantum_orchestrator_service_account" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for quantum optimization results"
  value       = google_bigquery_dataset.quantum_results.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.quantum_results.location
}

output "optimization_results_table" {
  description = "Full table ID for the optimization results table"
  value       = "${var.project_id}.${google_bigquery_dataset.quantum_results.dataset_id}.${google_bigquery_table.optimization_results.table_id}"
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}" : "Monitoring disabled"
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email[0].id : "Monitoring disabled"
}

# Scheduler Outputs
output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for periodic optimization"
  value       = var.enable_monitoring ? google_cloud_scheduler_job.quantum_optimization[0].name : "Scheduler disabled"
}

output "scheduler_job_schedule" {
  description = "Schedule of the Cloud Scheduler job"
  value       = var.enable_monitoring ? google_cloud_scheduler_job.quantum_optimization[0].schedule : "Scheduler disabled"
}

# Security Outputs
output "custom_quantum_role_id" {
  description = "ID of the custom IAM role for quantum computing access"
  value       = google_project_iam_custom_role.quantum_access.id
}

output "firewall_rules" {
  description = "List of firewall rules created for the quantum VPC"
  value = [
    google_compute_firewall.allow_internal.name,
    google_compute_firewall.allow_ssh.name
  ]
}

# Configuration Summary
output "quantum_configuration" {
  description = "Summary of quantum computing configuration"
  value = {
    quantum_processor_enabled = var.enable_quantum_processor
    quantum_processor_id     = var.quantum_processor_id
    default_portfolio_size   = var.default_portfolio_size
    default_risk_aversion    = var.default_risk_aversion
  }
}

# Usage Instructions
output "deployment_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    vertex_ai_access = "Access Vertex AI Workbench at: https://console.cloud.google.com/vertex-ai/workbench"
    function_testing = "Test the orchestration function by sending POST requests to the function URL"
    data_location   = "Upload quantum computing data to: gs://${google_storage_bucket.quantum_data.name}"
    monitoring      = var.enable_monitoring ? "View monitoring dashboard in Cloud Console" : "Enable monitoring variable to use dashboards"
  }
}

# API Endpoints for Integration
output "api_endpoints" {
  description = "API endpoints for external integration"
  value = {
    orchestration_function = google_cloudfunctions_function.quantum_orchestrator.https_trigger_url
    bigquery_dataset      = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.quantum_results.dataset_id}"
    storage_bucket        = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.quantum_data.name}?project=${var.project_id}"
  }
  sensitive = true
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Information about potential costs for the deployed resources"
  value = {
    vertex_ai_workbench = "~$50-150/month for ${var.notebook_machine_type} instance running 8h/day"
    cloud_functions     = "~$1-10/month for ${var.function_memory}MB function with moderate usage"
    cloud_storage       = "~$1-5/month for ${var.storage_class} storage with <100GB data"
    bigquery           = "~$1-20/month depending on query frequency and data size"
    monitoring         = "Free tier covers basic monitoring, ~$1-5/month for advanced features"
    note              = "Actual costs depend on usage patterns. Quantum processor access requires special pricing."
  }
}

# Resource Labels
output "applied_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Access Vertex AI Workbench and install quantum computing libraries",
    "2. Upload sample portfolio data to the Cloud Storage bucket",
    "3. Test the Cloud Function orchestrator with a simple API call",
    "4. Configure monitoring alerts for production use",
    "5. Request quantum processor access from Google Cloud if needed",
    "6. Review and customize the default portfolio optimization parameters"
  ]
}