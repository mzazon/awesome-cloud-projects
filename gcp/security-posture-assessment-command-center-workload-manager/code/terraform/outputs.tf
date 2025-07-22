# Output values for Security Posture Assessment Infrastructure
# These outputs provide important information about the deployed resources

# Project and Configuration Information
output "project_id" {
  description = "Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "resource_suffix" {
  description = "Suffix used for resource naming"
  value       = local.resource_suffix
}

# Security Command Center Information
output "security_command_center_organization" {
  description = "Organization ID configured for Security Command Center"
  value       = var.organization_id
}

output "security_notification_config_id" {
  description = "Security Command Center notification configuration ID"
  value       = google_scc_notification_config.security_findings.config_id
}

output "custom_detector_source_name" {
  description = "Security Command Center custom detector source name"
  value       = google_scc_source.custom_detector.name
}

# Pub/Sub Resources
output "security_events_topic_name" {
  description = "Name of the Pub/Sub topic for security events"
  value       = google_pubsub_topic.security_events.name
}

output "security_events_topic_id" {
  description = "Full resource ID of the security events Pub/Sub topic"
  value       = google_pubsub_topic.security_events.id
}

output "security_events_subscription_name" {
  description = "Name of the Pub/Sub subscription for security events"
  value       = google_pubsub_subscription.security_events_subscription.name
}

output "security_events_dlq_topic_name" {
  description = "Name of the dead letter queue topic for failed messages"
  value       = google_pubsub_topic.security_events_dlq.name
}

# Cloud Function Information
output "security_function_name" {
  description = "Name of the security remediation Cloud Function"
  value       = var.enable_automated_remediation ? google_cloudfunctions_function.security_remediation[0].name : null
}

output "security_function_url" {
  description = "URL of the security remediation Cloud Function"
  value       = var.enable_automated_remediation ? google_cloudfunctions_function.security_remediation[0].https_trigger_url : null
}

output "security_function_runtime" {
  description = "Runtime environment of the security remediation function"
  value       = var.function_runtime
}

output "security_function_memory" {
  description = "Memory allocation for the security remediation function (MB)"
  value       = var.function_memory_mb
}

# Storage Resources
output "security_logs_bucket_name" {
  description = "Name of the Cloud Storage bucket for security logs"
  value       = google_storage_bucket.security_logs.name
}

output "security_logs_bucket_url" {
  description = "URL of the Cloud Storage bucket for security logs"
  value       = google_storage_bucket.security_logs.url
}

output "security_logs_bucket_location" {
  description = "Location of the Cloud Storage bucket for security logs"
  value       = google_storage_bucket.security_logs.location
}

# Workload Manager Information
output "workload_manager_evaluation_id" {
  description = "ID of the Workload Manager security compliance evaluation"
  value       = var.enable_workload_manager ? google_workload_manager_evaluation.security_compliance[0].evaluation_id : null
}

output "workload_manager_evaluation_name" {
  description = "Full name of the Workload Manager evaluation"
  value       = var.enable_workload_manager ? google_workload_manager_evaluation.security_compliance[0].name : null
}

output "workload_manager_custom_rules" {
  description = "List of custom rules configured in Workload Manager"
  value       = var.workload_manager_rules
}

# Cloud Scheduler Information
output "security_evaluation_schedule" {
  description = "Cron schedule for automated security evaluations"
  value       = var.security_evaluation_schedule
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for security evaluations"
  value       = google_cloud_scheduler_job.security_evaluation_trigger.name
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the security automation service account"
  value       = local.service_account_email
}

output "service_account_name" {
  description = "Name of the security automation service account"
  value       = var.create_custom_service_account ? google_service_account.security_automation[0].name : null
}

output "service_account_roles" {
  description = "List of IAM roles assigned to the service account"
  value       = var.service_account_roles
}

# Monitoring and Alerting
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard for security metrics"
  value       = var.create_monitoring_dashboard ? google_monitoring_dashboard.security_posture[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the security posture monitoring dashboard"
  value       = var.create_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.security_posture[0].id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the alerting policy for critical security findings"
  value       = var.enable_critical_alert_notifications ? google_monitoring_alert_policy.critical_security_findings[0].name : null
}

# Budget Information
output "budget_name" {
  description = "Name of the billing budget for cost monitoring"
  value       = var.budget_amount > 0 ? google_billing_budget.security_posture_budget[0].display_name : null
}

output "budget_amount" {
  description = "Budget amount configured for cost monitoring"
  value       = var.budget_amount > 0 ? var.budget_amount : null
}

output "budget_threshold_percent" {
  description = "Budget threshold percentage for alerts"
  value       = var.budget_amount > 0 ? var.budget_threshold_percent : null
}

# API Services
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "securitycenter.googleapis.com",
    "workloadmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Security Configuration
output "security_posture_template" {
  description = "Security posture template used for baseline security controls"
  value       = var.security_posture_template
}

output "security_findings_filter" {
  description = "Filter used for Security Command Center findings notifications"
  value       = "state=\"ACTIVE\""
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

# URLs and Console Links
output "console_links" {
  description = "Direct links to Google Cloud Console for key resources"
  value = {
    security_command_center = "https://console.cloud.google.com/security/command-center"
    workload_manager       = "https://console.cloud.google.com/workload-manager"
    cloud_functions        = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    pubsub                 = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
    monitoring             = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    storage                = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    scheduler              = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    logging                = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    check_apis = "gcloud services list --enabled --project=${var.project_id}"
    list_topics = "gcloud pubsub topics list --project=${var.project_id}"
    check_function = var.enable_automated_remediation ? "gcloud functions describe ${google_cloudfunctions_function.security_remediation[0].name} --region=${var.region} --project=${var.project_id}" : null
    check_bucket = "gsutil ls -b gs://${google_storage_bucket.security_logs.name}"
    check_scheduler = "gcloud scheduler jobs list --project=${var.project_id}"
    check_workload_manager = var.enable_workload_manager ? "gcloud workload-manager evaluations list --location=${var.region} --project=${var.project_id}" : null
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    security_command_center = "~$50-100/month (Premium tier)"
    cloud_functions        = "~$0.40 per 1M invocations + compute time"
    pubsub                 = "~$0.40 per 1M messages"
    cloud_storage          = "~$0.020 per GB per month (Standard class)"
    cloud_scheduler        = "~$0.10 per job per month"
    monitoring             = "~$0.258 per 1M data points"
    total_estimate         = "~$55-120/month depending on usage"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure notification channels for security alerts",
    "2. Customize Workload Manager rules for your specific requirements",
    "3. Set up Security Command Center posture management",
    "4. Configure additional custom detectors based on your security policies",
    "5. Test the automated remediation function with sample security findings",
    "6. Set up regular security posture reviews and compliance reporting"
  ]
}