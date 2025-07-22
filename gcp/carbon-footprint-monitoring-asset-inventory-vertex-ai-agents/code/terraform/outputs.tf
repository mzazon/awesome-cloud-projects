# Project and Configuration Outputs
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for this carbon monitoring infrastructure"
  value       = local.random_suffix
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for carbon footprint analytics"
  value       = google_bigquery_dataset.carbon_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.carbon_analytics.location
}

output "asset_inventory_table_id" {
  description = "The full table ID for the asset inventory table"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.asset_inventory.table_id}"
}

output "carbon_emissions_table_id" {
  description = "The full table ID for the carbon emissions table"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.carbon_emissions.table_id}"
}

output "monthly_trends_view_id" {
  description = "The full view ID for the monthly carbon trends view"
  value       = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.${google_bigquery_table.monthly_carbon_trends.table_id}"
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for asset change notifications"
  value       = google_pubsub_topic.asset_changes.name
}

output "pubsub_topic_id" {
  description = "The full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.asset_changes.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription for asset changes"
  value       = google_pubsub_subscription.asset_changes_subscription.name
}

output "pubsub_dead_letter_topic_name" {
  description = "The name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.asset_changes_dead_letter.name
}

# Storage Outputs
output "carbon_data_bucket_name" {
  description = "The name of the Cloud Storage bucket for AI agent data and reports"
  value       = google_storage_bucket.carbon_data_bucket.name
}

output "carbon_data_bucket_url" {
  description = "The Cloud Storage bucket URL"
  value       = google_storage_bucket.carbon_data_bucket.url
}

output "carbon_data_bucket_self_link" {
  description = "The self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.carbon_data_bucket.self_link
}

# Service Account Outputs
output "asset_inventory_service_account_email" {
  description = "Email address of the Cloud Asset Inventory service account"
  value       = google_service_account.asset_inventory_sa.email
}

output "vertex_ai_service_account_email" {
  description = "Email address of the Vertex AI service account"
  value       = google_service_account.vertex_ai_sa.email
}

# Monitoring Outputs
output "carbon_emissions_metric_type" {
  description = "The metric type for carbon emissions monitoring"
  value       = google_monitoring_metric_descriptor.carbon_emissions_metric.type
}

output "alert_policy_name" {
  description = "The name of the carbon emissions alert policy"
  value       = google_monitoring_alert_policy.high_carbon_emissions.name
}

output "alert_policy_id" {
  description = "The ID of the carbon emissions alert policy"
  value       = google_monitoring_alert_policy.high_carbon_emissions.id
}

output "notification_channel_id" {
  description = "The ID of the email notification channel (if configured)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : "No email notification configured"
}

# Asset Inventory Configuration Outputs
output "asset_types_monitored" {
  description = "List of Google Cloud asset types being monitored"
  value       = var.asset_types_to_monitor
}

output "asset_content_type" {
  description = "Content type configuration for asset inventory feed"
  value       = var.asset_content_type
}

# CLI Commands for Manual Setup (since some resources require manual configuration)
output "cli_commands" {
  description = "CLI commands to complete the carbon monitoring setup"
  value = {
    create_asset_feed = "gcloud asset feeds create carbon-monitoring-feed --project=${var.project_id} --asset-types='${join(",", var.asset_types_to_monitor)}' --content-type=${var.asset_content_type} --pubsub-topic=projects/${var.project_id}/topics/${google_pubsub_topic.asset_changes.name}"
    
    configure_carbon_export = "gcloud alpha carbon-footprint export create --destination-table=${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.carbon_emissions --location=${var.region}"
    
    create_vertex_ai_agent = "gcloud alpha ai agents create sustainability-advisor --region=${var.region} --display-name='${var.agent_display_name}' --description='${var.agent_description}' --instruction='${var.agent_instruction}'"
    
    query_carbon_trends = "bq query --use_legacy_sql=false 'SELECT service, SUM(carbon_footprint_total_kgCO2e) as total_emissions FROM \\`${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.carbon_emissions\\` GROUP BY service ORDER BY total_emissions DESC LIMIT 5'"
  }
}

# Validation Outputs
output "bigquery_validation_query" {
  description = "SQL query to validate BigQuery setup and data ingestion"
  value = "SELECT COUNT(*) as asset_count, COUNT(DISTINCT asset_type) as asset_types FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.asset_inventory`"
}

output "carbon_emissions_validation_query" {
  description = "SQL query to validate carbon emissions data"
  value = "SELECT service, SUM(carbon_footprint_total_kgCO2e) as total_emissions FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.carbon_emissions` GROUP BY service ORDER BY total_emissions DESC LIMIT 5"
}

# Cost and Resource Information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs for the deployed resources"
  value = {
    bigquery_storage = "BigQuery storage: ~$0.02 per GB per month"
    bigquery_queries = "BigQuery queries: ~$5 per TB processed"
    pubsub_messages = "Pub/Sub: ~$0.40 per million messages"
    cloud_storage = "Cloud Storage: ~$0.020 per GB per month (Standard class)"
    monitoring = "Cloud Monitoring: Free tier includes basic alerting"
    vertex_ai = "Vertex AI: Pay-per-use based on agent interactions and model usage"
    total_estimate = "Estimated total: $50-150/month depending on data volume and usage"
  }
}

# Security and Compliance Outputs
output "security_considerations" {
  description = "Important security and compliance information"
  value = {
    data_encryption = "All data is encrypted at rest and in transit using Google Cloud managed encryption"
    access_control = "IAM roles follow least privilege principle"
    audit_logging = "All resource access is logged via Cloud Audit Logs"
    compliance = "Supports SOC 2, ISO 27001, and other compliance frameworks"
    carbon_methodology = "Carbon footprint calculations follow GHG Protocol Corporate Standard"
  }
}

# Next Steps and Integration Points
output "integration_endpoints" {
  description = "Key endpoints and identifiers for integrating with the carbon monitoring system"
  value = {
    bigquery_dataset = "${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}"
    pubsub_topic = "projects/${var.project_id}/topics/${google_pubsub_topic.asset_changes.name}"
    storage_bucket = "gs://${google_storage_bucket.carbon_data_bucket.name}"
    monitoring_workspace = "projects/${var.project_id}"
  }
}