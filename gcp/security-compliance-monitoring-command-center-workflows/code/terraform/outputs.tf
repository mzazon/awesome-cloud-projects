# Project and region information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

# Pub/Sub resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for security findings"
  value       = google_pubsub_topic.security_findings.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.security_findings.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.security_findings_subscription.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Function information
output "function_name" {
  description = "Name of the security processing Cloud Function"
  value       = google_cloudfunctions2_function.security_processor.name
}

output "function_url" {
  description = "URL of the security processing Cloud Function"
  value       = google_cloudfunctions2_function.security_processor.service_config[0].uri
}

output "function_service_account_email" {
  description = "Email of the Cloud Function service account"
  value       = var.create_service_accounts ? google_service_account.function_sa[0].email : null
}

# Cloud Workflows information
output "high_severity_workflow_name" {
  description = "Name of the high-severity security workflow"
  value       = google_workflows_workflow.high_severity.name
}

output "medium_severity_workflow_name" {
  description = "Name of the medium-severity security workflow"
  value       = google_workflows_workflow.medium_severity.name
}

output "low_severity_workflow_name" {
  description = "Name of the low-severity security workflow"
  value       = google_workflows_workflow.low_severity.name
}

output "workflow_service_account_email" {
  description = "Email of the workflows service account"
  value       = var.create_service_accounts ? google_service_account.workflow_sa[0].email : null
}

# Security Command Center information
output "scc_notification_name" {
  description = "Name of the Security Command Center notification configuration"
  value       = var.organization_id != "" ? google_scc_notification_config.security_findings_notification[0].name : null
}

output "scc_notification_id" {
  description = "Full resource ID of the Security Command Center notification"
  value       = var.organization_id != "" ? google_scc_notification_config.security_findings_notification[0].id : null
}

# Service account information
output "service_accounts" {
  description = "Service accounts created for the security system"
  value = var.create_service_accounts ? {
    function_sa = {
      name  = google_service_account.function_sa[0].name
      email = google_service_account.function_sa[0].email
      id    = google_service_account.function_sa[0].id
    }
    workflow_sa = {
      name  = google_service_account.workflow_sa[0].name
      email = google_service_account.workflow_sa[0].email
      id    = google_service_account.workflow_sa[0].id
    }
  } : null
}

# Storage bucket information
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.url
}

# Monitoring resources
output "monitoring_metrics" {
  description = "Log-based metrics created for monitoring"
  value = var.enable_monitoring ? {
    security_findings_processed = google_logging_metric.security_findings_processed[0].name
    workflow_executions       = google_logging_metric.workflow_executions[0].name
  } : null
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

output "alert_policy_id" {
  description = "ID of the high-severity findings alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_severity_findings[0].id : null
}

output "dashboard_id" {
  description = "ID of the compliance monitoring dashboard"
  value       = var.enable_monitoring && var.create_dashboard ? google_monitoring_dashboard.compliance_dashboard[0].id : null
}

# URLs and endpoints for easy access
output "console_urls" {
  description = "Google Cloud Console URLs for key resources"
  value = {
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.security_findings.name}?project=${var.project_id}"
    
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.security_processor.name}?project=${var.project_id}"
    
    workflows = {
      high_severity   = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.high_severity.name}?project=${var.project_id}"
      medium_severity = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.medium_severity.name}?project=${var.project_id}"
      low_severity    = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.low_severity.name}?project=${var.project_id}"
    }
    
    monitoring_dashboard = var.enable_monitoring && var.create_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.compliance_dashboard[0].id}?project=${var.project_id}" : null
    
    security_command_center = var.organization_id != "" ? "https://console.cloud.google.com/security/command-center/findings?organizationId=${var.organization_id}" : null
  }
}

# Resource naming information
output "resource_names" {
  description = "Names of all created resources for reference"
  value = {
    # Generated identifiers
    random_suffix = random_id.suffix.hex
    
    # Pub/Sub resources
    topic_name        = local.topic_name
    subscription_name = google_pubsub_subscription.security_findings_subscription.name
    dead_letter_topic = google_pubsub_topic.dead_letter.name
    
    # Compute resources
    function_name = local.function_name
    
    # Workflow resources
    high_severity_workflow   = local.high_severity_workflow
    medium_severity_workflow = local.medium_severity_workflow
    low_severity_workflow    = local.low_severity_workflow
    
    # Service accounts
    function_sa_name = var.create_service_accounts ? local.function_sa_name : null
    workflow_sa_name = var.create_service_accounts ? local.workflow_sa_name : null
    
    # Monitoring resources
    dashboard_name = local.dashboard_name
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the deployed security compliance monitoring system"
  value = {
    enabled_apis          = var.enable_apis ? length(var.required_apis) : 0
    created_workflows     = 3
    monitoring_enabled    = var.enable_monitoring
    dashboard_created     = var.enable_monitoring && var.create_dashboard
    notification_email    = var.notification_email != "" ? var.notification_email : "not configured"
    scc_integration      = var.organization_id != "" ? "enabled" : "disabled"
    service_accounts     = var.create_service_accounts ? 2 : 0
    environment          = var.environment
    resource_prefix      = var.resource_prefix
  }
}