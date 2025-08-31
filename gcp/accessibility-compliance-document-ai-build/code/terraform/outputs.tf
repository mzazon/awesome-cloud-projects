# =====================================================
# Terraform Outputs
# Output values for the accessibility compliance infrastructure
# =====================================================

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Document AI Outputs
output "document_ai_processor_id" {
  description = "The ID of the Document AI processor"
  value       = google_document_ai_processor.accessibility_processor.name
}

output "document_ai_processor_display_name" {
  description = "The display name of the Document AI processor"
  value       = google_document_ai_processor.accessibility_processor.display_name
}

output "document_ai_processor_type" {
  description = "The type of the Document AI processor"
  value       = google_document_ai_processor.accessibility_processor.type
}

# Storage Outputs
output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket for compliance reports"
  value       = google_storage_bucket.compliance_reports.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.compliance_reports.url
}

output "storage_bucket_self_link" {
  description = "The self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.compliance_reports.self_link
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for compliance alerts"
  value       = google_pubsub_topic.compliance_alerts.name
}

output "pubsub_topic_id" {
  description = "The ID of the Pub/Sub topic"
  value       = google_pubsub_topic.compliance_alerts.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.compliance_alerts_subscription.name
}

# Security Command Center Outputs
output "scc_source_name" {
  description = "The name of the Security Command Center source"
  value       = var.organization_id != "" ? google_scc_source.accessibility_compliance[0].name : null
}

output "scc_source_id" {
  description = "The ID of the Security Command Center source"
  value       = var.organization_id != "" ? google_scc_source.accessibility_compliance[0].id : null
}

output "scc_notification_config_name" {
  description = "The name of the Security Command Center notification configuration"
  value       = var.organization_id != "" ? google_scc_notification_config.accessibility_alerts[0].name : null
}

# Cloud Functions Outputs
output "cloud_function_name" {
  description = "The name of the Cloud Function for compliance notifications"
  value       = google_cloudfunctions_function.compliance_notifier.name
}

output "cloud_function_url" {
  description = "The URL of the Cloud Function"
  value       = google_cloudfunctions_function.compliance_notifier.https_trigger_url
}

output "cloud_function_service_account" {
  description = "The service account email for the Cloud Function"
  value       = google_cloudfunctions_function.compliance_notifier.service_account_email
}

# Cloud Build Outputs
output "github_build_trigger_id" {
  description = "The ID of the GitHub-based Cloud Build trigger"
  value       = var.github_repo_name != "" && var.github_repo_owner != "" ? google_cloudbuild_trigger.accessibility_testing[0].trigger_id : null
}

output "github_build_trigger_name" {
  description = "The name of the GitHub-based Cloud Build trigger"
  value       = var.github_repo_name != "" && var.github_repo_owner != "" ? google_cloudbuild_trigger.accessibility_testing[0].name : null
}

output "manual_build_trigger_id" {
  description = "The ID of the manual Cloud Build trigger"
  value       = google_cloudbuild_trigger.accessibility_manual.trigger_id
}

output "manual_build_trigger_name" {
  description = "The name of the manual Cloud Build trigger"
  value       = google_cloudbuild_trigger.accessibility_manual.name
}

# Build Configuration Outputs
output "build_substitutions" {
  description = "The substitution variables used in Cloud Build"
  value = {
    _PROCESSOR_ID = google_document_ai_processor.accessibility_processor.name
    _BUCKET_NAME  = google_storage_bucket.compliance_reports.name
    _TOPIC_NAME   = google_pubsub_topic.compliance_alerts.name
    _PROJECT_ID   = var.project_id
    _REGION       = var.region
  }
  sensitive = false
}

# Service Account Information
output "cloudbuild_service_account" {
  description = "The Cloud Build service account email"
  value       = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

output "project_number" {
  description = "The GCP project number"
  value       = data.google_project.project.number
}

# API Services
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.enable_apis
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Configuration for CLI Usage
output "cli_commands" {
  description = "Useful CLI commands for managing the infrastructure"
  value = {
    # Document AI commands
    test_processor = "gcloud documentai processors list --location=${var.region}"
    
    # Storage commands
    list_reports = "gsutil ls gs://${google_storage_bucket.compliance_reports.name}/reports/"
    
    # Pub/Sub commands
    publish_test_message = "gcloud pubsub topics publish ${google_pubsub_topic.compliance_alerts.name} --message='test message'"
    
    # Cloud Build commands
    submit_manual_build = "gcloud builds submit --config=cloudbuild.yaml --substitutions=_PROCESSOR_ID=${google_document_ai_processor.accessibility_processor.name},_BUCKET_NAME=${google_storage_bucket.compliance_reports.name},_TOPIC_NAME=${google_pubsub_topic.compliance_alerts.name}"
    
    # Security Command Center commands (if org_id provided)
    list_scc_findings = var.organization_id != "" ? "gcloud scc findings list --organization=${var.organization_id} --source=${google_scc_source.accessibility_compliance[0].name} --filter='category=\"ACCESSIBILITY_COMPLIANCE\"'" : "N/A - No organization ID provided"
    
    # Function commands
    test_function = "gcloud functions call ${google_cloudfunctions_function.compliance_notifier.name} --region=${var.region}"
  }
}

# Getting Started Information
output "getting_started" {
  description = "Next steps to complete the setup"
  value = {
    step_1 = "Upload your cloudbuild.yaml configuration file to your repository"
    step_2 = "Create sample HTML files with accessibility violations for testing"
    step_3 = "Configure your repository connection for Cloud Build triggers"
    step_4 = "Test the pipeline with a manual build: ${google_cloudbuild_trigger.accessibility_manual.name}"
    step_5 = "Monitor compliance reports in: gs://${google_storage_bucket.compliance_reports.name}/reports/"
    step_6 = var.organization_id != "" ? "View findings in Security Command Center console" : "Provide organization_id variable to enable Security Command Center integration"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the infrastructure (USD)"
  value = {
    document_ai          = "$0.015 per page processed (first 1,000 pages free monthly)"
    cloud_build         = "$0.003 per build minute (first 120 minutes free daily)"
    cloud_storage       = "$0.020 per GB for Standard storage"
    pub_sub             = "$40 per million messages"
    cloud_functions     = "$0.0000004 per invocation + $0.0000025 per GB-second"
    security_cmd_center = "$0.00 for standard tier findings"
    total_estimated     = "$15-25 monthly for moderate usage"
  }
}

# Monitoring and Observability
output "monitoring_resources" {
  description = "Resources for monitoring the accessibility compliance system"
  value = {
    cloud_build_logs     = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    function_logs        = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.compliance_notifier.name}?project=${var.project_id}"
    storage_browser      = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.compliance_reports.name}?project=${var.project_id}"
    pubsub_monitoring    = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.compliance_alerts.name}?project=${var.project_id}"
    scc_dashboard        = var.organization_id != "" ? "https://console.cloud.google.com/security/command-center/findings?organizationId=${var.organization_id}" : "N/A - No organization ID provided"
  }
}