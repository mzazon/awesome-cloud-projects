# Output Values for API Governance and Compliance Monitoring
# This file defines all output values that provide important information
# about the deployed infrastructure for verification and integration

# ============================================================================
# PROJECT AND RESOURCE IDENTIFICATION
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The primary region where resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# APIGEE X ORGANIZATION AND ENVIRONMENT
# ============================================================================

output "apigee_organization_id" {
  description = "The Apigee X organization ID"
  value       = var.enable_apigee_organization ? google_apigee_organization.main[0].id : null
}

output "apigee_organization_name" {
  description = "The Apigee X organization name"
  value       = var.enable_apigee_organization ? google_apigee_organization.main[0].name : null
}

output "apigee_environment_name" {
  description = "The Apigee environment name for API governance"
  value       = var.enable_apigee_organization ? google_apigee_environment.governance[0].name : null
}

output "apigee_environment_id" {
  description = "The Apigee environment ID"
  value       = var.enable_apigee_organization ? google_apigee_environment.governance[0].id : null
}

output "apigee_analytics_region" {
  description = "The analytics region for Apigee X organization"
  value       = var.enable_apigee_organization ? google_apigee_organization.main[0].analytics_region : null
}

# ============================================================================
# CLOUD STORAGE RESOURCES
# ============================================================================

output "function_source_bucket" {
  description = "Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the function source code bucket"
  value       = google_storage_bucket.function_source.url
}

output "api_configs_bucket" {
  description = "Cloud Storage bucket for API configuration files"
  value       = google_storage_bucket.api_configs.name
}

output "api_configs_bucket_url" {
  description = "URL of the API configuration bucket"
  value       = google_storage_bucket.api_configs.url
}

# ============================================================================
# BIGQUERY RESOURCES
# ============================================================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for API governance logs"
  value       = var.enable_bigquery_export ? google_bigquery_dataset.api_logs[0].dataset_id : null
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = var.enable_bigquery_export ? google_bigquery_dataset.api_logs[0].location : null
}

output "bigquery_table_id" {
  description = "BigQuery table ID for API events"
  value       = var.enable_bigquery_export ? google_bigquery_table.api_events[0].table_id : null
}

output "bigquery_table_full_name" {
  description = "Full BigQuery table name for API events"
  value       = var.enable_bigquery_export ? "${var.project_id}.${google_bigquery_dataset.api_logs[0].dataset_id}.${google_bigquery_table.api_events[0].table_id}" : null
}

# ============================================================================
# PUB/SUB RESOURCES
# ============================================================================

output "governance_topic_name" {
  description = "Pub/Sub topic name for API governance events"
  value       = google_pubsub_topic.api_governance_events.name
}

output "governance_topic_id" {
  description = "Pub/Sub topic ID for API governance events"
  value       = google_pubsub_topic.api_governance_events.id
}

output "compliance_subscription_name" {
  description = "Pub/Sub subscription name for compliance monitoring"
  value       = google_pubsub_subscription.compliance_monitoring.name
}

output "dead_letter_topic_name" {
  description = "Pub/Sub dead letter topic name"
  value       = google_pubsub_topic.dead_letter.name
}

output "event_schema_id" {
  description = "Pub/Sub schema ID for API events"
  value       = google_pubsub_schema.api_event_schema.id
}

# ============================================================================
# CLOUD FUNCTIONS
# ============================================================================

output "compliance_monitor_function_name" {
  description = "Name of the compliance monitoring Cloud Function"
  value       = google_cloudfunctions2_function.compliance_monitor.name
}

output "compliance_monitor_function_uri" {
  description = "URI of the compliance monitoring Cloud Function"
  value       = google_cloudfunctions2_function.compliance_monitor.service_config[0].uri
}

output "policy_enforcer_function_name" {
  description = "Name of the policy enforcement Cloud Function"
  value       = google_cloudfunctions2_function.policy_enforcer.name
}

output "policy_enforcer_function_uri" {
  description = "URI of the policy enforcement Cloud Function"
  value       = google_cloudfunctions2_function.policy_enforcer.service_config[0].uri
}

# ============================================================================
# SERVICE ACCOUNTS
# ============================================================================

output "compliance_monitor_service_account" {
  description = "Email of the compliance monitor service account"
  value       = google_service_account.compliance_monitor_sa.email
}

output "policy_enforcer_service_account" {
  description = "Email of the policy enforcer service account"
  value       = google_service_account.policy_enforcer_sa.email
}

output "eventarc_service_account" {
  description = "Email of the Eventarc service account"
  value       = var.enable_eventarc_triggers ? google_service_account.eventarc_sa[0].email : null
}

# ============================================================================
# CLOUD LOGGING
# ============================================================================

output "apigee_audit_log_sink_name" {
  description = "Name of the Apigee audit log sink"
  value       = var.enable_bigquery_export ? google_logging_project_sink.apigee_audit_logs[0].name : null
}

output "compliance_events_sink_name" {
  description = "Name of the compliance events log sink"
  value       = google_logging_project_sink.compliance_events.name
}

output "apigee_audit_sink_writer_identity" {
  description = "Writer identity for the Apigee audit log sink"
  value       = var.enable_bigquery_export ? google_logging_project_sink.apigee_audit_logs[0].writer_identity : null
}

output "compliance_events_sink_writer_identity" {
  description = "Writer identity for the compliance events log sink"
  value       = google_logging_project_sink.compliance_events.writer_identity
}

# ============================================================================
# EVENTARC TRIGGERS
# ============================================================================

output "api_config_changes_trigger_name" {
  description = "Name of the API configuration changes Eventarc trigger"
  value       = var.enable_eventarc_triggers ? google_eventarc_trigger.api_config_changes[0].name : null
}

output "security_violations_trigger_name" {
  description = "Name of the security violations Eventarc trigger"
  value       = var.enable_eventarc_triggers ? google_eventarc_trigger.security_violations[0].name : null
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

output "email_notification_channel" {
  description = "Email notification channel for monitoring alerts"
  value       = var.enable_monitoring_alerts ? google_monitoring_notification_channel.email_alerts[0].name : null
}

output "compliance_violations_alert_policy" {
  description = "Alert policy name for compliance violations"
  value       = var.enable_monitoring_alerts ? google_monitoring_alert_policy.compliance_violations[0].name : null
}

output "apigee_infrastructure_alert_policy" {
  description = "Alert policy name for Apigee infrastructure issues"
  value       = var.enable_monitoring_alerts && var.enable_apigee_organization ? google_monitoring_alert_policy.apigee_infrastructure[0].name : null
}

# ============================================================================
# CONFIGURATION INFORMATION
# ============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the project"
  value       = [for api in google_project_service.required_apis : api.service]
}

output "monitoring_configuration" {
  description = "Monitoring configuration summary"
  value = {
    notification_email     = var.monitoring_notification_email
    error_rate_threshold   = var.monitoring_error_rate_threshold
    alert_auto_close       = var.monitoring_alert_auto_close
    alerts_enabled         = var.enable_monitoring_alerts
  }
}

output "function_configuration" {
  description = "Cloud Functions configuration summary"
  value = {
    runtime           = var.function_runtime
    memory           = var.function_memory
    timeout          = var.function_timeout
    min_instances    = var.function_min_instances
    max_instances    = var.function_max_instances
  }
}

output "bigquery_configuration" {
  description = "BigQuery configuration summary"
  value = var.enable_bigquery_export ? {
    dataset_id              = google_bigquery_dataset.api_logs[0].dataset_id
    location               = google_bigquery_dataset.api_logs[0].location
    table_expiration_days  = var.bigquery_table_expiration_days
    export_enabled         = var.enable_bigquery_export
  } : null
}

# ============================================================================
# URLS FOR MANAGEMENT CONSOLES
# ============================================================================

output "apigee_console_url" {
  description = "URL to the Apigee X management console"
  value       = var.enable_apigee_organization ? "https://console.cloud.google.com/apigee/proxies?project=${var.project_id}" : null
}

output "bigquery_console_url" {
  description = "URL to the BigQuery console for the dataset"
  value       = var.enable_bigquery_export ? "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.api_logs[0].dataset_id}" : null
}

output "cloud_functions_console_url" {
  description = "URL to the Cloud Functions console"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

output "monitoring_console_url" {
  description = "URL to the Cloud Monitoring console"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

output "logging_console_url" {
  description = "URL to the Cloud Logging console"
  value       = "https://console.cloud.google.com/logs?project=${var.project_id}"
}

# ============================================================================
# VALIDATION COMMANDS
# ============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_apigee_org = var.enable_apigee_organization ? "gcloud alpha apigee organizations describe ${google_apigee_organization.main[0].name}" : null
    check_functions  = "gcloud functions list --project=${var.project_id}"
    check_bigquery   = var.enable_bigquery_export ? "bq ls --project_id=${var.project_id} ${google_bigquery_dataset.api_logs[0].dataset_id}" : null
    check_pubsub     = "gcloud pubsub topics list --project=${var.project_id}"
    check_storage    = "gsutil ls -b gs://${google_storage_bucket.function_source.name}"
  }
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed API governance infrastructure"
  value = {
    apigee_organization_enabled = var.enable_apigee_organization
    bigquery_export_enabled     = var.enable_bigquery_export
    monitoring_alerts_enabled   = var.enable_monitoring_alerts
    eventarc_triggers_enabled   = var.enable_eventarc_triggers
    total_functions_deployed    = 2
    total_storage_buckets       = 2
    total_pubsub_topics         = 2
    resource_suffix             = random_id.suffix.hex
  }
}