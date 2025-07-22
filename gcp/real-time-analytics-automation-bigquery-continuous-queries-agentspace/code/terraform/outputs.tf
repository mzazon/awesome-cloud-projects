# Project and Resource Identification Outputs
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.suffix
}

# Pub/Sub Infrastructure Outputs
output "pubsub_topic_raw_events" {
  description = "Name of the Pub/Sub topic for raw streaming events"
  value       = google_pubsub_topic.raw_events.name
}

output "pubsub_topic_insights" {
  description = "Name of the Pub/Sub topic for processed insights"
  value       = google_pubsub_topic.insights.name
}

output "pubsub_topic_dead_letter" {
  description = "Name of the Pub/Sub dead letter topic"
  value       = google_pubsub_topic.dead_letter.name
}

output "pubsub_subscription_raw_events" {
  description = "Name of the Pub/Sub subscription for BigQuery consumption"
  value       = google_pubsub_subscription.raw_events_bq.name
}

output "pubsub_subscription_insights" {
  description = "Name of the Pub/Sub subscription for workflow triggers"
  value       = google_pubsub_subscription.insights_workflow.name
}

# Pub/Sub Topic URLs for publishing
output "pubsub_topic_raw_events_url" {
  description = "Full URL for publishing to the raw events topic"
  value       = "projects/${var.project_id}/topics/${google_pubsub_topic.raw_events.name}"
}

output "pubsub_topic_insights_url" {
  description = "Full URL for publishing to the insights topic"
  value       = "projects/${var.project_id}/topics/${google_pubsub_topic.insights.name}"
}

# BigQuery Infrastructure Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for real-time analytics"
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics.location
}

output "bigquery_table_processed_events" {
  description = "Full table reference for processed events"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.processed_events.table_id}"
}

output "bigquery_table_insights" {
  description = "Full table reference for insights"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.insights.table_id}"
}

# BigQuery Table URLs for console access
output "bigquery_console_url_dataset" {
  description = "Google Cloud Console URL for the BigQuery dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.analytics.dataset_id}"
}

output "bigquery_console_url_processed_events" {
  description = "Google Cloud Console URL for the processed events table"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.analytics.dataset_id}!3s${google_bigquery_table.processed_events.table_id}"
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the Agentspace analytics service account"
  value       = var.create_service_account ? google_service_account.agentspace_analytics[0].email : "No service account created"
}

output "service_account_unique_id" {
  description = "Unique ID of the Agentspace analytics service account"
  value       = var.create_service_account ? google_service_account.agentspace_analytics[0].unique_id : "No service account created"
}

# Cloud Workflows Outputs
output "workflow_name" {
  description = "Name of the Cloud Workflows automation workflow"
  value       = google_workflows_workflow.analytics_automation.name
}

output "workflow_id" {
  description = "Full resource ID of the Cloud Workflows workflow"
  value       = google_workflows_workflow.analytics_automation.id
}

output "workflow_console_url" {
  description = "Google Cloud Console URL for the Cloud Workflows workflow"
  value       = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.analytics_automation.name}?project=${var.project_id}"
}

# Continuous Query Outputs
output "continuous_query_job_id" {
  description = "Job ID for the BigQuery continuous query (for manual deployment)"
  value       = local.continuous_query_job_id
}

output "continuous_query_sql_file" {
  description = "Path to the generated continuous query SQL file"
  value       = var.enable_continuous_query ? local_file.continuous_query_sql[0].filename : "Continuous query disabled"
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "alert_notification_email" {
  description = "Email address for monitoring alerts"
  value       = var.alert_email != "" ? var.alert_email : "No alert email configured"
}

output "monitoring_alert_policies" {
  description = "List of created monitoring alert policy names"
  value = var.enable_monitoring ? [
    var.enable_monitoring ? google_monitoring_alert_policy.bigquery_job_failure[0].display_name : "",
    var.enable_monitoring ? google_monitoring_alert_policy.pubsub_backlog[0].display_name : ""
  ] : []
}

# Deployment Commands and Instructions
output "deployment_commands" {
  description = "Commands to complete the deployment"
  value = {
    # gcloud commands for manual steps
    enable_continuous_query = "bq query --use_legacy_sql=false --job_timeout=0 --continuous --job_id='${local.continuous_query_job_id}' \"$(cat ${var.enable_continuous_query ? local_file.continuous_query_sql[0].filename : "continuous_query.sql"})\""
    
    # Publishing test data
    publish_test_event = "gcloud pubsub topics publish ${google_pubsub_topic.raw_events.name} --message='{\"event_id\":\"test-001\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",\"user_id\":\"user_123\",\"event_type\":\"purchase\",\"value\":150.0,\"metadata\":{\"source\":\"web_app\"}}'"
    
    # Viewing logs
    view_workflow_logs = "gcloud logging read 'resource.type=\"workflow\" AND logName=\"projects/${var.project_id}/logs/analytics-automation\"' --limit=10 --format=json"
    
    # Monitoring continuous query
    check_continuous_query = "bq show -j '${local.continuous_query_job_id}'"
  }
}

# Data Simulation Script Information
output "data_simulation_setup" {
  description = "Information about setting up data simulation for testing"
  value = {
    install_pubsub_client = "pip install google-cloud-pubsub"
    topic_name           = google_pubsub_topic.raw_events.name
    project_id          = var.project_id
    sample_command      = "python simulate_data.py ${var.project_id} ${google_pubsub_topic.raw_events.name} 100"
  }
}

# Resource Costs and Optimization
output "cost_optimization_notes" {
  description = "Important notes about cost optimization"
  value = {
    bigquery_slots = "Continuous queries consume BigQuery slots continuously. Consider slot reservations for predictable costs."
    pubsub_retention = "Pub/Sub messages are retained for ${var.pubsub_message_retention_duration}. Adjust based on your recovery requirements."
    monitoring_alerts = "Monitoring policies will incur small charges. Disable monitoring to reduce costs in development environments."
    cleanup_reminder = "Run 'terraform destroy' to clean up all resources and avoid ongoing charges."
  }
}

# Validation Queries
output "validation_queries" {
  description = "BigQuery queries for validating the deployment"
  value = {
    check_processed_events = "SELECT COUNT(*) as event_count, MAX(timestamp) as latest_event FROM `${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.processed_events.table_id}`"
    check_insights = "SELECT insight_type, confidence, COUNT(*) as insight_count FROM `${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.insights.table_id}` GROUP BY insight_type, confidence"
    recent_insights = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.insights.table_id}` WHERE generated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) ORDER BY generated_at DESC LIMIT 10"
  }
}

# Security and Access Information
output "security_recommendations" {
  description = "Security best practices and recommendations"
  value = {
    service_account_key = "Do not download service account keys. Use Workload Identity or service account impersonation instead."
    iam_principle = "The service account follows least privilege principle with minimal required permissions."
    data_encryption = "All data is encrypted at rest and in transit using Google Cloud default encryption."
    audit_logging = "Enable audit logging for production environments to track access and changes."
  }
}