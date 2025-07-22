# ============================================================================
# Outputs for Real-Time Supply Chain Visibility Infrastructure
# ============================================================================

# ============================================================================
# Project and General Information
# ============================================================================

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.resource_suffix.hex
}

# ============================================================================
# Cloud Spanner Outputs
# ============================================================================

output "spanner_instance_name" {
  description = "The name of the Cloud Spanner instance"
  value       = google_spanner_instance.supply_chain_instance.name
}

output "spanner_instance_id" {
  description = "The full resource ID of the Cloud Spanner instance"
  value       = google_spanner_instance.supply_chain_instance.id
}

output "spanner_database_name" {
  description = "The name of the Cloud Spanner database"
  value       = google_spanner_database.supply_chain_database.name
}

output "spanner_database_id" {
  description = "The full resource ID of the Cloud Spanner database"
  value       = google_spanner_database.supply_chain_database.id
}

output "spanner_instance_config" {
  description = "The configuration of the Cloud Spanner instance"
  value       = google_spanner_instance.supply_chain_instance.config
}

output "spanner_instance_state" {
  description = "The state of the Cloud Spanner instance"
  value       = google_spanner_instance.supply_chain_instance.state
}

output "spanner_connection_string" {
  description = "Connection string for the Cloud Spanner database"
  value       = "projects/${var.project_id}/instances/${google_spanner_instance.supply_chain_instance.name}/databases/${google_spanner_database.supply_chain_database.name}"
}

# ============================================================================
# Cloud Pub/Sub Outputs
# ============================================================================

output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic"
  value       = google_pubsub_topic.logistics_events.name
}

output "pubsub_topic_id" {
  description = "The full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.logistics_events.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.logistics_events_subscription.name
}

output "pubsub_subscription_id" {
  description = "The full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.logistics_events_subscription.id
}

output "pubsub_subscription_path" {
  description = "The full path of the Pub/Sub subscription"
  value       = google_pubsub_subscription.logistics_events_subscription.path
}

# ============================================================================
# BigQuery Outputs
# ============================================================================

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset"
  value       = google_bigquery_dataset.supply_chain_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.supply_chain_analytics.location
}

output "bigquery_shipment_analytics_table_id" {
  description = "The ID of the shipment analytics table"
  value       = google_bigquery_table.shipment_analytics.table_id
}

output "bigquery_event_analytics_table_id" {
  description = "The ID of the event analytics table"
  value       = google_bigquery_table.event_analytics.table_id
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.supply_chain_analytics.dataset_id}"
}

output "bigquery_query_examples" {
  description = "Example queries for the BigQuery tables"
  value = {
    shipment_summary = "SELECT status, COUNT(*) as count FROM `${var.project_id}.${google_bigquery_dataset.supply_chain_analytics.dataset_id}.${google_bigquery_table.shipment_analytics.table_id}` GROUP BY status"
    event_summary = "SELECT event_type, COUNT(*) as count FROM `${var.project_id}.${google_bigquery_dataset.supply_chain_analytics.dataset_id}.${google_bigquery_table.event_analytics.table_id}` WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY) GROUP BY event_type"
  }
}

# ============================================================================
# Cloud Storage Outputs
# ============================================================================

output "storage_bucket_name" {
  description = "The name of the Cloud Storage bucket"
  value       = google_storage_bucket.dataflow_staging.name
}

output "storage_bucket_url" {
  description = "The URL of the Cloud Storage bucket"
  value       = google_storage_bucket.dataflow_staging.url
}

output "storage_bucket_self_link" {
  description = "The self link of the Cloud Storage bucket"
  value       = google_storage_bucket.dataflow_staging.self_link
}

# ============================================================================
# Service Account Outputs
# ============================================================================

output "service_account_email" {
  description = "The email address of the service account"
  value       = var.create_service_accounts ? google_service_account.supply_chain_sa[0].email : null
}

output "service_account_id" {
  description = "The ID of the service account"
  value       = var.create_service_accounts ? google_service_account.supply_chain_sa[0].id : null
}

output "service_account_unique_id" {
  description = "The unique ID of the service account"
  value       = var.create_service_accounts ? google_service_account.supply_chain_sa[0].unique_id : null
}

# ============================================================================
# Dataflow Outputs
# ============================================================================

output "dataflow_job_name" {
  description = "The name of the Dataflow job"
  value       = local.dataflow_job_name
}

output "dataflow_staging_location" {
  description = "The staging location for Dataflow"
  value       = "gs://${google_storage_bucket.dataflow_staging.name}/staging"
}

output "dataflow_temp_location" {
  description = "The temporary location for Dataflow"
  value       = "gs://${google_storage_bucket.dataflow_staging.name}/temp"
}

output "dataflow_template_location" {
  description = "Location where the Dataflow template should be stored"
  value       = "gs://${google_storage_bucket.dataflow_staging.name}/templates"
}

output "dataflow_job_id" {
  description = "The ID of the Dataflow job (if created)"
  value       = length(google_dataflow_flex_template_job.supply_chain_streaming) > 0 ? google_dataflow_flex_template_job.supply_chain_streaming[0].job_id : null
}

output "dataflow_job_state" {
  description = "The state of the Dataflow job (if created)"
  value       = length(google_dataflow_flex_template_job.supply_chain_streaming) > 0 ? google_dataflow_flex_template_job.supply_chain_streaming[0].state : null
}

# ============================================================================
# Monitoring and Logging Outputs
# ============================================================================

output "monitoring_alert_policy_ids" {
  description = "IDs of the monitoring alert policies"
  value = {
    dataflow_job_failed = var.enable_monitoring ? google_monitoring_alert_policy.dataflow_job_failed[0].name : null
    spanner_high_cpu    = var.enable_monitoring ? google_monitoring_alert_policy.spanner_high_cpu[0].name : null
  }
}

output "logging_sink_name" {
  description = "The name of the logging sink"
  value       = var.enable_logging ? google_logging_project_sink.dataflow_logs[0].name : null
}

output "logging_sink_destination" {
  description = "The destination of the logging sink"
  value       = var.enable_logging ? google_logging_project_sink.dataflow_logs[0].destination : null
}

# ============================================================================
# Connection and Configuration Information
# ============================================================================

output "gcloud_commands" {
  description = "Useful gcloud commands for interacting with the infrastructure"
  value = {
    # Spanner commands
    spanner_list_databases = "gcloud spanner databases list --instance=${google_spanner_instance.supply_chain_instance.name}"
    spanner_query = "gcloud spanner databases execute-sql ${google_spanner_database.supply_chain_database.name} --instance=${google_spanner_instance.supply_chain_instance.name} --sql=\"SELECT COUNT(*) FROM Events\""
    
    # Pub/Sub commands
    pubsub_publish_test = "gcloud pubsub topics publish ${google_pubsub_topic.logistics_events.name} --message='{\"event_id\":\"test-123\",\"event_type\":\"test\",\"timestamp\":\"2024-01-01T00:00:00Z\"}'"
    pubsub_pull_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.logistics_events_subscription.name} --limit=10"
    
    # BigQuery commands
    bigquery_query_events = "bq query --use_legacy_sql=false \"SELECT event_type, COUNT(*) as count FROM \\`${var.project_id}.${google_bigquery_dataset.supply_chain_analytics.dataset_id}.${google_bigquery_table.event_analytics.table_id}\\` GROUP BY event_type\""
    bigquery_query_shipments = "bq query --use_legacy_sql=false \"SELECT status, COUNT(*) as count FROM \\`${var.project_id}.${google_bigquery_dataset.supply_chain_analytics.dataset_id}.${google_bigquery_table.shipment_analytics.table_id}\\` GROUP BY status\""
    
    # Dataflow commands
    dataflow_list_jobs = "gcloud dataflow jobs list --region=${var.region}"
    dataflow_job_details = "gcloud dataflow jobs describe ${local.dataflow_job_name} --region=${var.region}"
  }
}

output "console_urls" {
  description = "URLs to access resources in the Google Cloud Console"
  value = {
    spanner_instance = "https://console.cloud.google.com/spanner/instances/${google_spanner_instance.supply_chain_instance.name}/details/databases?project=${var.project_id}"
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.logistics_events.name}?project=${var.project_id}"
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.supply_chain_analytics.dataset_id}"
    dataflow_jobs = "https://console.cloud.google.com/dataflow/jobs?project=${var.project_id}"
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.dataflow_staging.name}?project=${var.project_id}"
    monitoring = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logging = "https://console.cloud.google.com/logs?project=${var.project_id}"
  }
}

# ============================================================================
# Sample Data and Testing
# ============================================================================

output "sample_event_json" {
  description = "Sample JSON event for testing the pipeline"
  value = jsonencode({
    event_id = "sample-event-001"
    shipment_id = "SH123456"
    order_id = "ORD98765"
    event_type = "in_transit"
    carrier_id = "UPS"
    location = "Chicago, IL"
    timestamp = "2024-01-15T10:30:00Z"
    tracking_number = "1Z999AA1234567890"
    metadata = {
      temperature = 22
      weight_kg = 5.5
    }
  })
}

output "deployment_instructions" {
  description = "Instructions for completing the deployment"
  value = {
    step1 = "Deploy the Terraform infrastructure: terraform apply"
    step2 = "Build and deploy the Dataflow pipeline as a Flex Template"
    step3 = "Enable the Dataflow job by setting the count to 1 in main.tf"
    step4 = "Test the pipeline by publishing messages to the Pub/Sub topic"
    step5 = "Monitor the pipeline using the provided console URLs"
  }
}

# ============================================================================
# Cost and Resource Summary
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    spanner_instance = "~$90-180 (1 node, regional)"
    pubsub_topic = "~$5-20 (depends on message volume)"
    bigquery_storage = "~$5-10 (depends on data volume)"
    dataflow_job = "~$100-300 (depends on worker hours)"
    storage_bucket = "~$1-5 (staging and temp files)"
    monitoring_logging = "~$10-30 (depends on log volume)"
    total_estimate = "~$200-500+ per month"
    note = "Costs vary significantly based on usage patterns and data volumes"
  }
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    spanner_instances = 1
    spanner_databases = 1
    pubsub_topics = 1
    pubsub_subscriptions = 1
    bigquery_datasets = 1
    bigquery_tables = 2
    storage_buckets = 1
    service_accounts = var.create_service_accounts ? 1 : 0
    dataflow_jobs = 0  # Created separately
    monitoring_alerts = var.enable_monitoring ? 2 : 0
    logging_sinks = var.enable_logging ? 1 : 0
  }
}