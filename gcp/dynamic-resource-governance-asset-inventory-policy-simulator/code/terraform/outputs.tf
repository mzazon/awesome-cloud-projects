# Outputs for Dynamic Resource Governance Infrastructure
# This file provides important information about the deployed governance system

# Project and Environment Information
output "project_id" {
  description = "Google Cloud Project ID where the governance system is deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for the governance system"
  value       = var.environment
}

output "resource_suffix" {
  description = "Generated suffix used for resource naming"
  value       = local.resource_suffix
}

# Service Account Information
output "governance_service_account" {
  description = "Email address of the governance automation service account"
  value       = google_service_account.governance_sa.email
}

output "governance_service_account_id" {
  description = "Unique ID of the governance automation service account"
  value       = google_service_account.governance_sa.unique_id
}

# Pub/Sub Configuration
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for asset change notifications"
  value       = google_pubsub_topic.asset_changes.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.asset_changes.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for compliance processing"
  value       = google_pubsub_subscription.compliance_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.compliance_subscription.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letters.name
}

# Asset Inventory Configuration
output "asset_feed_name" {
  description = "Name of the Cloud Asset Inventory feed"
  value       = google_cloud_asset_project_feed.governance_project_feed.feed_id
}

output "asset_feed_id" {
  description = "Full resource ID of the Cloud Asset Inventory feed"
  value       = google_cloud_asset_project_feed.governance_project_feed.id
}

output "asset_content_type" {
  description = "Content type configured for the asset feed"
  value       = var.asset_content_type
}

output "monitored_asset_types" {
  description = "List of asset types being monitored by the governance system"
  value       = var.asset_types
}

# Cloud Functions Information
output "asset_analyzer_function" {
  description = "Information about the Asset Analyzer Cloud Function"
  value = {
    name        = google_cloudfunctions2_function.asset_analyzer.name
    location    = google_cloudfunctions2_function.asset_analyzer.location
    runtime     = var.functions_runtime
    memory_mb   = var.asset_analyzer_config.memory_mb
    timeout_sec = var.asset_analyzer_config.timeout_seconds
    trigger     = "Pub/Sub Topic: ${google_pubsub_topic.asset_changes.name}"
  }
}

output "policy_validator_function" {
  description = "Information about the Policy Validator Cloud Function"
  value = {
    name        = google_cloudfunctions2_function.policy_validator.name
    location    = google_cloudfunctions2_function.policy_validator.location
    runtime     = var.functions_runtime
    memory_mb   = var.policy_validator_config.memory_mb
    timeout_sec = var.policy_validator_config.timeout_seconds
    trigger     = "HTTP"
    url         = google_cloudfunctions2_function.policy_validator.service_config[0].uri
  }
}

output "compliance_engine_function" {
  description = "Information about the Compliance Engine Cloud Function"
  value = {
    name        = google_cloudfunctions2_function.compliance_engine.name
    location    = google_cloudfunctions2_function.compliance_engine.location
    runtime     = var.functions_runtime
    memory_mb   = var.compliance_engine_config.memory_mb
    timeout_sec = var.compliance_engine_config.timeout_seconds
    trigger     = "Pub/Sub Topic: ${google_pubsub_topic.asset_changes.name}"
  }
}

# Storage Configuration
output "functions_bucket" {
  description = "Cloud Storage bucket used for Cloud Functions source code"
  value = {
    name     = google_storage_bucket.functions_bucket.name
    location = google_storage_bucket.functions_bucket.location
    url      = google_storage_bucket.functions_bucket.url
  }
}

output "governance_logs_bucket" {
  description = "Cloud Storage bucket used for governance logs"
  value = {
    name     = google_storage_bucket.governance_logs.name
    location = google_storage_bucket.governance_logs.location
    url      = google_storage_bucket.governance_logs.url
  }
}

# Monitoring Configuration
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled for the governance system"
  value       = var.enable_monitoring
}

output "alert_policy_id" {
  description = "ID of the governance system alert policy (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.governance_alerts[0].name : null
}

output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for governance events"
  value       = google_logging_project_sink.governance_sink.name
}

output "logging_sink_writer_identity" {
  description = "Writer identity for the governance logging sink"
  value       = google_logging_project_sink.governance_sink.writer_identity
}

# Compliance Configuration
output "compliance_policies" {
  description = "Configured compliance policies for the governance system"
  value       = var.compliance_policies
}

output "high_risk_asset_types" {
  description = "List of asset types classified as high risk"
  value       = var.high_risk_asset_types
}

# API Services
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs for the governance system"
  value       = var.required_apis
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the governance system"
  value = {
    test_governance = "Create a test resource to trigger governance workflows: gcloud compute instances create test-vm --zone=${var.zone}"
    view_logs      = "View governance logs: gcloud logging read 'resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.resource_prefix}-.*\"' --limit=10"
    check_alerts   = "Check monitoring alerts: gcloud alpha monitoring policies list --filter='displayName:\"Governance System Alerts\"'"
    pubsub_pull    = "Pull messages from subscription: gcloud pubsub subscriptions pull ${google_pubsub_subscription.compliance_subscription.name} --auto-ack --limit=5"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the governance system deployment"
  value = {
    check_asset_feed = "gcloud asset feeds list --project=${var.project_id}"
    check_functions  = "gcloud functions list --regions=${var.region} --project=${var.project_id}"
    check_pubsub     = "gcloud pubsub topics list --project=${var.project_id}"
    check_service_account = "gcloud iam service-accounts list --filter='email:${google_service_account.governance_sa.email}' --project=${var.project_id}"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details for the governance system"
  value = {
    service_account_roles = var.governance_roles
    function_ingress_settings = {
      asset_analyzer    = var.asset_analyzer_config.ingress_settings
      policy_validator  = var.policy_validator_config.ingress_settings
      compliance_engine = var.compliance_engine_config.ingress_settings
    }
    pubsub_ack_deadline = var.pubsub_ack_deadline
    message_retention   = var.pubsub_message_retention
  }
}

# Cost Information
output "cost_estimation" {
  description = "Estimated monthly costs for the governance system (USD)"
  value = {
    note = "Actual costs depend on usage patterns and resource creation frequency"
    cloud_functions = "~$5-15/month (based on execution frequency)"
    pubsub = "~$2-5/month (based on message volume)"
    storage = "~$1-3/month (for function source code and logs)"
    monitoring = "~$2-5/month (for alerts and metrics)"
    asset_inventory = "Included in Cloud Asset Inventory API quotas"
    estimated_total = "$10-28/month for moderate enterprise usage"
  }
}

# Cleanup Instructions
output "cleanup_instructions" {
  description = "Instructions for cleaning up the governance system"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "Delete any test resources created during validation",
      "Check for any remaining Cloud Functions logs",
      "Verify all Pub/Sub messages have been processed"
    ]
    cost_verification = "Check Google Cloud Console billing to verify resource deletion"
  }
}