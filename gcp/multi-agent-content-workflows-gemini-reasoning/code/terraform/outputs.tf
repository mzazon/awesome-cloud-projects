# =============================================================================
# Outputs for GCP Multi-Agent Content Workflows Infrastructure
# =============================================================================
# This file defines all outputs from the multi-agent content processing
# infrastructure deployment for integration and verification purposes.
# =============================================================================

# Storage Resources Outputs
# -----------------------------------------------------------------------------
output "content_bucket_name" {
  description = "Name of the Cloud Storage bucket for content processing"
  value       = google_storage_bucket.content_bucket.name
}

output "content_bucket_url" {
  description = "URL of the Cloud Storage bucket for content processing"
  value       = google_storage_bucket.content_bucket.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

# Cloud Workflows Outputs
# -----------------------------------------------------------------------------
output "workflow_name" {
  description = "Name of the Cloud Workflows workflow for content analysis"
  value       = google_workflows_workflow.content_analysis_workflow.name
}

output "workflow_id" {
  description = "Full resource ID of the Cloud Workflows workflow"
  value       = google_workflows_workflow.content_analysis_workflow.id
}

output "workflow_region" {
  description = "Region where the Cloud Workflows workflow is deployed"
  value       = google_workflows_workflow.content_analysis_workflow.region
}

# Cloud Function Outputs
# -----------------------------------------------------------------------------
output "function_name" {
  description = "Name of the Cloud Function trigger"
  value       = google_cloudfunctions2_function.content_trigger.name
}

output "function_url" {
  description = "URL of the Cloud Function trigger"
  value       = google_cloudfunctions2_function.content_trigger.service_config[0].uri
}

output "function_location" {
  description = "Location where the Cloud Function is deployed"
  value       = google_cloudfunctions2_function.content_trigger.location
}

# Service Account Outputs
# -----------------------------------------------------------------------------
output "service_account_email" {
  description = "Email address of the content intelligence service account"
  value       = google_service_account.content_intelligence_sa.email
}

output "service_account_id" {
  description = "ID of the content intelligence service account"
  value       = google_service_account.content_intelligence_sa.account_id
}

output "service_account_unique_id" {
  description = "Unique ID of the content intelligence service account"
  value       = google_service_account.content_intelligence_sa.unique_id
}

# Pub/Sub Resources Outputs
# -----------------------------------------------------------------------------
output "notification_topic_name" {
  description = "Name of the Pub/Sub topic for workflow notifications"
  value       = google_pubsub_topic.workflow_notifications.name
}

output "notification_topic_id" {
  description = "Full resource ID of the Pub/Sub notification topic"
  value       = google_pubsub_topic.workflow_notifications.id
}

output "monitoring_subscription_name" {
  description = "Name of the Pub/Sub subscription for workflow monitoring"
  value       = google_pubsub_subscription.workflow_monitoring.name
}

# Configuration and Setup Outputs
# -----------------------------------------------------------------------------
output "gemini_config_path" {
  description = "Cloud Storage path to the Gemini configuration file"
  value       = "gs://${google_storage_bucket.content_bucket.name}/${google_storage_bucket_object.gemini_config.name}"
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
  sensitive   = false
}

# API and Integration Endpoints
# -----------------------------------------------------------------------------
output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the project"
  value       = [for api in google_project_service.apis : api.service]
}

# Content Processing Configuration
# -----------------------------------------------------------------------------
output "supported_content_types" {
  description = "Configuration of supported content types for processing"
  value = {
    text_formats  = var.content_processing_config.supported_text_formats
    image_formats = var.content_processing_config.supported_image_formats
    video_formats = var.content_processing_config.supported_video_formats
    max_file_size = "${var.content_processing_config.max_file_size_mb}MB"
  }
}

# Security and Access Configuration
# -----------------------------------------------------------------------------
output "iam_roles_assigned" {
  description = "List of IAM roles assigned to the service account"
  value       = [for role in google_project_iam_member.content_intelligence_roles : role.role]
}

# Storage Configuration Details
# -----------------------------------------------------------------------------
output "storage_configuration" {
  description = "Configuration details of the content storage bucket"
  value = {
    storage_class         = google_storage_bucket.content_bucket.storage_class
    location             = google_storage_bucket.content_bucket.location
    versioning_enabled   = google_storage_bucket.content_bucket.versioning[0].enabled
    uniform_bucket_access = google_storage_bucket.content_bucket.uniform_bucket_level_access
  }
}

# Monitoring and Alerting Resources
# -----------------------------------------------------------------------------
output "alert_policy_name" {
  description = "Name of the monitoring alert policy for workflow failures"
  value       = google_monitoring_alert_policy.workflow_failures.display_name
}

output "alert_policy_enabled" {
  description = "Whether the monitoring alert policy is enabled"
  value       = google_monitoring_alert_policy.workflow_failures.enabled
}

# DLP Template (if enabled)
# -----------------------------------------------------------------------------
output "dlp_template_name" {
  description = "Name of the DLP inspect template (if DLP is enabled)"
  value       = var.enable_dlp ? google_data_loss_prevention_inspect_template.content_inspection[0].name : null
}

# Network Configuration (if dedicated network is created)
# -----------------------------------------------------------------------------
output "vpc_network_name" {
  description = "Name of the dedicated VPC network (if created)"
  value       = var.create_dedicated_network ? google_compute_network.content_intelligence_vpc[0].name : null
}

output "vpc_subnet_name" {
  description = "Name of the VPC subnet (if dedicated network is created)"
  value       = var.create_dedicated_network ? google_compute_subnetwork.content_intelligence_subnet[0].name : null
}

output "vpc_connector_name" {
  description = "Name of the VPC connector (if dedicated network is created)"
  value       = var.create_dedicated_network ? google_vpc_access_connector.content_intelligence_connector[0].name : null
}

# Sample Content Information
# -----------------------------------------------------------------------------
output "sample_content_created" {
  description = "Whether sample content was created for testing"
  value       = var.create_sample_content
}

output "sample_content_path" {
  description = "Path to the sample content file (if created)"
  value       = var.create_sample_content ? "gs://${google_storage_bucket.content_bucket.name}/${google_storage_bucket_object.sample_text_content[0].name}" : null
}

# Usage Instructions and Next Steps
# -----------------------------------------------------------------------------
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    workflow_trigger = "Upload content to gs://${google_storage_bucket.content_bucket.name}/input/ to trigger processing"
    monitor_executions = "gcloud workflows executions list --workflow=${google_workflows_workflow.content_analysis_workflow.name} --location=${var.region}"
    view_results = "gsutil ls gs://${google_storage_bucket.content_bucket.name}/results/"
    function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.content_trigger.name} --region=${var.region}"
  }
}

# Cost Estimation Information
# -----------------------------------------------------------------------------
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for different usage patterns"
  value = {
    note = "Costs vary based on actual usage - these are estimates for planning"
    low_usage = {
      description = "~100 files/month, basic processing"
      estimate_usd = "50-100"
      breakdown = "Storage: $5, AI APIs: $30-60, Functions: $10-20, Workflows: $5-15"
    }
    medium_usage = {
      description = "~1000 files/month, regular processing"
      estimate_usd = "200-400"
      breakdown = "Storage: $20, AI APIs: $150-300, Functions: $20-50, Workflows: $10-50"
    }
    high_usage = {
      description = "~10000 files/month, intensive processing"
      estimate_usd = "1000-2000"
      breakdown = "Storage: $100, AI APIs: $800-1500, Functions: $50-200, Workflows: $50-300"
    }
  }
}

# Integration Examples
# -----------------------------------------------------------------------------
output "integration_examples" {
  description = "Examples for integrating with the deployed infrastructure"
  value = {
    upload_content = {
      cli_command = "gsutil cp your-file.txt gs://${google_storage_bucket.content_bucket.name}/input/"
      description = "Upload content to trigger automatic processing"
    }
    monitor_workflow = {
      cli_command = "gcloud workflows executions describe EXECUTION_ID --workflow=${google_workflows_workflow.content_analysis_workflow.name} --location=${var.region}"
      description = "Monitor specific workflow execution"
    }
    download_results = {
      cli_command = "gsutil cp gs://${google_storage_bucket.content_bucket.name}/results/your-file_analysis.json ./"
      description = "Download analysis results"
    }
    configure_notifications = {
      pubsub_topic = google_pubsub_topic.workflow_notifications.name
      description = "Subscribe to workflow notifications for real-time updates"
    }
  }
}

# Resource Management Information
# -----------------------------------------------------------------------------
output "resource_labels" {
  description = "Labels applied to all resources for organization"
  value       = var.labels
}

output "cleanup_commands" {
  description = "Commands to clean up resources when no longer needed"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "gsutil -m rm -r gs://${google_storage_bucket.content_bucket.name}",
      "gcloud workflows delete ${google_workflows_workflow.content_analysis_workflow.name} --location=${var.region}",
      "gcloud functions delete ${google_cloudfunctions2_function.content_trigger.name} --region=${var.region}"
    ]
  }
}