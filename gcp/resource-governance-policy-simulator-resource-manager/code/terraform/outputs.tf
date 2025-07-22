# Outputs Configuration for GCP Resource Governance Solution
# This file defines all output values from the governance infrastructure

output "project_id" {
  description = "The GCP project ID where governance resources are deployed"
  value       = var.project_id
}

output "organization_id" {
  description = "The GCP organization ID where policies are applied"
  value       = var.organization_id
}

output "governance_function_name" {
  description = "Name of the Cloud Function handling governance automation"
  value       = google_cloudfunctions2_function.governance_automation.name
}

output "governance_function_url" {
  description = "URL of the governance automation Cloud Function"
  value       = google_cloudfunctions2_function.governance_automation.service_config[0].uri
}

output "governance_topic_name" {
  description = "Name of the Pub/Sub topic for governance events"
  value       = google_pubsub_topic.governance_events.name
}

output "governance_topic_id" {
  description = "Full resource ID of the Pub/Sub topic for governance events"
  value       = google_pubsub_topic.governance_events.id
}

output "governance_bucket_name" {
  description = "Name of the Cloud Storage bucket for governance reports"
  value       = google_storage_bucket.governance_reports.name
}

output "governance_bucket_url" {
  description = "URL of the Cloud Storage bucket for governance reports"
  value       = google_storage_bucket.governance_reports.url
}

output "policy_simulator_service_account_email" {
  description = "Email address of the policy simulator service account"
  value       = google_service_account.policy_simulator.email
}

output "billing_governance_service_account_email" {
  description = "Email address of the billing governance service account"
  value       = google_service_account.billing_governance.email
}

output "governance_function_service_account_email" {
  description = "Email address of the governance function service account"
  value       = google_service_account.governance_function.email
}

output "governance_audit_schedule" {
  description = "Cron schedule for governance audits"
  value       = var.audit_schedule
}

output "cost_monitoring_schedule" {
  description = "Cron schedule for cost monitoring"
  value       = var.cost_monitoring_schedule
}

output "enabled_apis" {
  description = "List of APIs enabled for the governance solution"
  value       = keys(google_project_service.required_apis)
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for governance analytics (if enabled)"
  value       = var.enable_asset_inventory ? google_bigquery_dataset.governance_analytics[0].dataset_id : null
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location for governance analytics (if enabled)"
  value       = var.enable_asset_inventory ? google_bigquery_dataset.governance_analytics[0].location : null
}

output "billing_budget_name" {
  description = "Name of the billing budget for governance monitoring (if enabled)"
  value       = var.enable_billing_monitoring && var.billing_account != "" ? google_billing_budget.governance_budget[0].display_name : null
}

output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for governance violations"
  value       = google_monitoring_alert_policy.governance_violations.display_name
}

output "allowed_compute_regions" {
  description = "List of approved regions for compute resources"
  value       = var.allowed_compute_regions
}

output "required_resource_labels" {
  description = "List of required labels for all resources"
  value       = var.required_resource_labels
}

output "resource_labels" {
  description = "Common labels applied to all governance resources"
  value       = local.common_labels
}

output "scheduler_jobs" {
  description = "Information about created Cloud Scheduler jobs"
  value = {
    governance_audit = {
      name     = google_cloud_scheduler_job.governance_audit.name
      schedule = google_cloud_scheduler_job.governance_audit.schedule
    }
    cost_monitoring = var.enable_billing_monitoring ? {
      name     = google_cloud_scheduler_job.cost_monitoring[0].name
      schedule = google_cloud_scheduler_job.cost_monitoring[0].schedule
    } : null
  }
}

output "deployment_configuration" {
  description = "Summary of deployment configuration and enabled features"
  value = {
    environment              = var.environment
    team                    = var.team
    cost_center             = var.cost_center
    policy_simulation       = var.enable_policy_simulation
    billing_monitoring      = var.enable_billing_monitoring
    asset_inventory         = var.enable_asset_inventory
    budget_amount           = var.budget_amount
    budget_threshold        = var.budget_threshold_percent
  }
}

output "validation_commands" {
  description = "Commands to validate the governance deployment"
  value = {
    check_function_status = "gcloud functions describe ${google_cloudfunctions2_function.governance_automation.name} --region=${var.region} --gen2"
    list_scheduler_jobs   = "gcloud scheduler jobs list --location=${var.region}"
    test_pubsub_topic     = "gcloud pubsub topics publish ${google_pubsub_topic.governance_events.name} --message='{\"test\":true}'"
    check_bucket_objects  = "gsutil ls gs://${google_storage_bucket.governance_reports.name}/"
    view_function_logs    = "gcloud logging read 'resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.governance_automation.name}' --limit=10"
  }
}

output "cleanup_commands" {
  description = "Commands to clean up governance resources"
  value = {
    delete_scheduler_jobs = "gcloud scheduler jobs delete governance-audit-job cost-monitoring-job --location=${var.region} --quiet"
    delete_function      = "gcloud functions delete ${google_cloudfunctions2_function.governance_automation.name} --region=${var.region} --gen2 --quiet"
    delete_bucket        = "gsutil -m rm -r gs://${google_storage_bucket.governance_reports.name}"
    delete_topic         = "gcloud pubsub topics delete ${google_pubsub_topic.governance_events.name} --quiet"
  }
}

output "governance_endpoints" {
  description = "Key endpoints and resources for governance monitoring"
  value = {
    function_trigger_url = google_cloudfunctions2_function.governance_automation.service_config[0].uri
    pubsub_topic        = google_pubsub_topic.governance_events.id
    storage_bucket      = "gs://${google_storage_bucket.governance_reports.name}"
    bigquery_dataset    = var.enable_asset_inventory ? "projects/${var.project_id}/datasets/${google_bigquery_dataset.governance_analytics[0].dataset_id}" : null
  }
}