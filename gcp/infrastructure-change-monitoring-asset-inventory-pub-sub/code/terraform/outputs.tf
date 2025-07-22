# ==============================================================================
# Infrastructure Change Monitoring Outputs
# ==============================================================================
# This file defines outputs that provide important information about the
# deployed infrastructure monitoring solution, including resource identifiers,
# endpoints, and operational details needed for management and integration.

# ==============================================================================
# Core Resource Identifiers
# ==============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# ==============================================================================
# Pub/Sub Resources
# ==============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic receiving asset change notifications"
  value       = google_pubsub_topic.asset_changes.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.asset_changes.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for Cloud Functions processing"
  value       = google_pubsub_subscription.asset_changes.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.asset_changes.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed message processing"
  value       = google_pubsub_topic.dead_letter.name
}

# ==============================================================================
# Cloud Functions Resources
# ==============================================================================

output "cloud_function_name" {
  description = "Name of the Cloud Function processing asset changes"
  value       = google_cloudfunctions_function.asset_processor.name
}

output "cloud_function_url" {
  description = "HTTPS trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.asset_processor.https_trigger_url
}

output "cloud_function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "cloud_function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

# ==============================================================================
# BigQuery Resources
# ==============================================================================

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset storing audit data"
  value       = google_bigquery_dataset.infrastructure_audit.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.infrastructure_audit.location
}

output "bigquery_table_id" {
  description = "ID of the BigQuery table storing asset change records"
  value       = google_bigquery_table.asset_changes.table_id
}

output "bigquery_table_full_id" {
  description = "Full table ID for BigQuery queries (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}"
}

# ==============================================================================
# Cloud Asset Inventory Feed
# ==============================================================================

output "asset_feed_name" {
  description = "Name of the Cloud Asset Inventory feed"
  value       = google_cloud_asset_project_feed.infrastructure_feed.feed_id
}

output "asset_feed_full_name" {
  description = "Full resource name of the Cloud Asset Inventory feed"
  value       = google_cloud_asset_project_feed.infrastructure_feed.name
}

output "monitored_asset_types" {
  description = "List of asset types being monitored by the feed"
  value       = var.monitored_asset_types
}

# ==============================================================================
# Monitoring and Alerting
# ==============================================================================

output "monitoring_notification_channels" {
  description = "List of Cloud Monitoring notification channels for alerts"
  value       = var.enable_alerting ? google_monitoring_notification_channel.email[*].name : []
}

output "alert_policies" {
  description = "Map of created alert policies with their display names and IDs"
  value = var.enable_alerting ? {
    high_change_rate = {
      display_name = google_monitoring_alert_policy.high_change_rate[0].display_name
      name         = google_monitoring_alert_policy.high_change_rate[0].name
    }
    function_errors = {
      display_name = google_monitoring_alert_policy.function_errors[0].display_name
      name         = google_monitoring_alert_policy.function_errors[0].name
    }
  } : {}
}

output "change_rate_threshold" {
  description = "Configured threshold for infrastructure change rate alerts"
  value       = var.change_rate_threshold
}

# ==============================================================================
# Service Account and IAM
# ==============================================================================

output "function_service_account_id" {
  description = "Unique ID of the Cloud Function service account"
  value       = google_service_account.function_sa.unique_id
}

output "function_service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = google_service_account.function_sa.email
}

# ==============================================================================
# Operational Information
# ==============================================================================

output "audit_data_retention_days" {
  description = "Number of days audit data will be retained in BigQuery"
  value       = var.audit_data_retention_days
}

output "function_configuration" {
  description = "Configuration details of the deployed Cloud Function"
  value = {
    runtime         = google_cloudfunctions_function.asset_processor.runtime
    memory_mb       = google_cloudfunctions_function.asset_processor.available_memory_mb
    timeout_seconds = google_cloudfunctions_function.asset_processor.timeout
    entry_point     = google_cloudfunctions_function.asset_processor.entry_point
  }
}

output "pubsub_configuration" {
  description = "Configuration details of Pub/Sub resources"
  value = {
    topic_retention_duration     = google_pubsub_topic.asset_changes.message_retention_duration
    subscription_ack_deadline    = google_pubsub_subscription.asset_changes.ack_deadline_seconds
    subscription_retention       = google_pubsub_subscription.asset_changes.message_retention_duration
    dead_letter_max_attempts     = google_pubsub_subscription.asset_changes.dead_letter_policy[0].max_delivery_attempts
  }
}

# ==============================================================================
# Query Examples and Operational Commands
# ==============================================================================

output "sample_bigquery_queries" {
  description = "Sample BigQuery queries for analyzing infrastructure changes"
  value = {
    recent_changes = "SELECT timestamp, asset_name, asset_type, change_type FROM `${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) ORDER BY timestamp DESC LIMIT 100"
    
    change_summary = "SELECT change_type, asset_type, COUNT(*) as count FROM `${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY) GROUP BY change_type, asset_type ORDER BY count DESC"
    
    project_activity = "SELECT project_id, COUNT(*) as change_count FROM `${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) GROUP BY project_id ORDER BY change_count DESC"
    
    hourly_trends = "SELECT EXTRACT(HOUR FROM timestamp) as hour, COUNT(*) as changes FROM `${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) GROUP BY hour ORDER BY hour"
  }
}

output "monitoring_commands" {
  description = "Useful gcloud commands for monitoring the solution"
  value = {
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.asset_processor.name} --region=${var.region} --limit=50"
    
    check_pubsub_metrics = "gcloud pubsub topics describe ${google_pubsub_topic.asset_changes.name}"
    
    check_subscription_metrics = "gcloud pubsub subscriptions describe ${google_pubsub_subscription.asset_changes.name}"
    
    check_asset_feed = "gcloud asset feeds describe ${google_cloud_asset_project_feed.infrastructure_feed.feed_id} --project=${var.project_id}"
    
    test_bigquery_access = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as total_changes FROM `${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}`'"
  }
}

# ==============================================================================
# Resource URLs and Console Links
# ==============================================================================

output "console_links" {
  description = "Google Cloud Console links for managing deployed resources"
  value = {
    asset_feed = "https://console.cloud.google.com/assets/feeds?project=${var.project_id}"
    
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.asset_changes.name}?project=${var.project_id}"
    
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.asset_processor.name}?project=${var.project_id}"
    
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.infrastructure_audit.dataset_id}"
    
    monitoring_alerts = "https://console.cloud.google.com/monitoring/alerting?project=${var.project_id}"
    
    logs_explorer = "https://console.cloud.google.com/logs/query?project=${var.project_id}&query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D%22${google_cloudfunctions_function.asset_processor.name}%22"
  }
}

# ==============================================================================
# Validation and Testing Information
# ==============================================================================

output "validation_steps" {
  description = "Steps to validate the infrastructure monitoring solution"
  value = {
    step_1 = "Verify asset feed is active: gcloud asset feeds list --project=${var.project_id}"
    step_2 = "Check Pub/Sub topic subscriptions: gcloud pubsub topics list-subscriptions ${google_pubsub_topic.asset_changes.name}"
    step_3 = "Test BigQuery access: bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.infrastructure_audit.dataset_id}.${google_bigquery_table.asset_changes.table_id}` LIMIT 5'"
    step_4 = "Monitor function logs: gcloud functions logs read ${google_cloudfunctions_function.asset_processor.name} --region=${var.region}"
    step_5 = "Create test resource to trigger change: gcloud compute addresses create test-address-validation --region=${var.region}"
    step_6 = "Verify change recorded in BigQuery (wait 2-3 minutes after creating test resource)"
    step_7 = "Clean up test resource: gcloud compute addresses delete test-address-validation --region=${var.region} --quiet"
  }
}

output "troubleshooting_info" {
  description = "Troubleshooting information for common issues"
  value = {
    function_not_triggering = "Check if service account ${google_service_account.function_sa.email} has cloudfunctions.invoker role and Pub/Sub subscription is configured correctly"
    
    no_data_in_bigquery = "Verify Cloud Function logs for errors and ensure BigQuery dataset permissions are correctly configured"
    
    feed_not_publishing = "Asset feeds can take up to 10 minutes to become active. Check feed status with: gcloud asset feeds describe ${google_cloud_asset_project_feed.infrastructure_feed.feed_id}"
    
    permission_errors = "Ensure the Cloud Function service account has bigquery.dataEditor and monitoring.metricWriter roles"
    
    high_costs = "Monitor BigQuery slot usage and consider adjusting audit_data_retention_days variable to reduce storage costs"
  }
}