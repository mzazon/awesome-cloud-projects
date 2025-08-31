# Output values for Smart City Infrastructure Monitoring solution
# These outputs provide important information for verification and integration

# Project and Infrastructure Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Service Account Information
output "iot_service_account_email" {
  description = "Email address of the IoT service account for device authentication"
  value       = google_service_account.iot_sensors.email
}

output "iot_service_account_unique_id" {
  description = "Unique ID of the IoT service account"
  value       = google_service_account.iot_sensors.unique_id
}

# Pub/Sub Infrastructure
output "sensor_telemetry_topic_name" {
  description = "Name of the main sensor telemetry Pub/Sub topic"
  value       = google_pubsub_topic.sensor_telemetry.name
}

output "sensor_telemetry_topic_id" {
  description = "Full resource ID of the sensor telemetry topic"
  value       = google_pubsub_topic.sensor_telemetry.id
}

output "dead_letter_queue_topic_name" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.dlq.name
}

output "bigquery_subscription_name" {
  description = "Name of the BigQuery processing subscription"
  value       = google_pubsub_subscription.bigquery_streaming.name
}

output "ml_subscription_name" {
  description = "Name of the ML processing subscription"
  value       = google_pubsub_subscription.ml_processing.name
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for sensor data"
  value       = google_bigquery_dataset.smart_city_data.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.smart_city_data.location
}

output "sensor_readings_table_id" {
  description = "Full table ID for sensor readings (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.smart_city_data.dataset_id}.${google_bigquery_table.sensor_readings.table_id}"
}

output "anomalies_table_id" {
  description = "Full table ID for anomaly detection results"
  value       = "${var.project_id}.${google_bigquery_dataset.smart_city_data.dataset_id}.${google_bigquery_table.anomalies.table_id}"
}

output "sensor_metrics_table_id" {
  description = "Full table ID for aggregated sensor metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.smart_city_data.dataset_id}.${google_bigquery_table.sensor_metrics.table_id}"
}

# Cloud Storage
output "ml_artifacts_bucket_name" {
  description = "Name of the Cloud Storage bucket for ML artifacts"
  value       = google_storage_bucket.ml_artifacts.name
}

output "ml_artifacts_bucket_url" {
  description = "GS URL of the ML artifacts bucket"
  value       = google_storage_bucket.ml_artifacts.url
}

output "ml_artifacts_bucket_self_link" {
  description = "Self-link of the ML artifacts bucket"
  value       = google_storage_bucket.ml_artifacts.self_link
}

# Cloud Function
output "sensor_processor_function_name" {
  description = "Name of the sensor data processing Cloud Function"
  value       = google_cloudfunctions_function.sensor_processor.name
}

output "sensor_processor_function_url" {
  description = "HTTPS trigger URL of the Cloud Function (if applicable)"
  value       = google_cloudfunctions_function.sensor_processor.https_trigger_url
}

output "sensor_processor_function_source_archive" {
  description = "Cloud Storage path to the function source archive"
  value       = "gs://${google_storage_bucket.ml_artifacts.name}/${google_storage_bucket_object.function_source.name}"
}

# Vertex AI Resources
output "vertex_ai_dataset_name" {
  description = "Name of the Vertex AI dataset for ML training"
  value       = google_vertex_ai_dataset.sensor_data.name
}

output "vertex_ai_dataset_display_name" {
  description = "Display name of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.sensor_data.display_name
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = var.vertex_ai_region
}

# Monitoring Resources
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard"
  value       = var.dashboard_enabled ? google_monitoring_dashboard.smart_city_dashboard[0].id : null
}

output "high_message_rate_alert_policy_name" {
  description = "Name of the high message rate alert policy"
  value       = var.alert_policy_enabled ? google_monitoring_alert_policy.high_message_rate[0].name : null
}

output "function_errors_alert_policy_name" {
  description = "Name of the Cloud Function errors alert policy"
  value       = var.alert_policy_enabled ? google_monitoring_alert_policy.function_errors[0].name : null
}

# Logging
output "log_sink_name" {
  description = "Name of the centralized logging sink"
  value       = google_logging_project_sink.smart_city_logs.name
}

output "log_sink_writer_identity" {
  description = "Writer identity for the log sink"
  value       = google_logging_project_sink.smart_city_logs.writer_identity
}

# Budget Information
output "budget_name" {
  description = "Name of the budget alert (if enabled)"
  value       = var.budget_amount > 0 ? google_billing_budget.smart_city_budget[0].display_name : null
}

output "budget_amount" {
  description = "Monthly budget amount in USD"
  value       = var.budget_amount
}

# API Endpoints and Connection Information
output "pubsub_publish_endpoint" {
  description = "Pub/Sub endpoint for publishing sensor data"
  value       = "https://pubsub.googleapis.com/v1/projects/${var.project_id}/topics/${google_pubsub_topic.sensor_telemetry.name}:publish"
}

output "bigquery_query_endpoint" {
  description = "BigQuery endpoint for running queries"
  value       = "https://bigquery.googleapis.com/bigquery/v2/projects/${var.project_id}/queries"
}

output "vertex_ai_endpoint" {
  description = "Vertex AI endpoint for the region"
  value       = "https://${var.vertex_ai_region}-aiplatform.googleapis.com"
}

# Security and Access Information
output "service_account_key_info" {
  description = "Information about service account authentication"
  value = {
    email                = google_service_account.iot_sensors.email
    pubsub_publisher_role = "roles/pubsub.publisher"
    bigquery_editor_role  = "roles/bigquery.dataEditor"
    monitoring_writer_role = "roles/monitoring.metricWriter"
  }
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Data Quality and Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and observability"
  value = {
    cloud_console_project    = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    pubsub_topics           = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
    bigquery_datasets       = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    cloud_functions         = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    monitoring_dashboards   = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
    vertex_ai_datasets      = "https://console.cloud.google.com/vertex-ai/datasets?project=${var.project_id}"
    cloud_storage_buckets   = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation and optimization"
  value = {
    pubsub_messages_per_month_estimate = "Depends on sensor frequency and device count"
    bigquery_storage_estimate         = "Varies based on sensor data volume"
    cloud_function_invocations        = "Matches Pub/Sub message volume"
    vertex_ai_training_cost           = "Depends on model complexity and training frequency"
    monitoring_cost                   = "Based on metrics and log volume"
  }
}

# Network and Security Configuration
output "security_configuration" {
  description = "Security configuration details"
  value = {
    uniform_bucket_access      = var.enable_uniform_bucket_level_access
    public_access_prevention   = var.enable_public_access_prevention
    private_google_access     = var.enable_private_google_access
    service_account_based_auth = true
    iam_least_privilege       = true
  }
}

# Getting Started Information
output "getting_started" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    authenticate_with_service_account = "gcloud auth activate-service-account --key-file=path/to/service-account-key.json"
    publish_test_message             = "gcloud pubsub topics publish ${google_pubsub_topic.sensor_telemetry.name} --message='{\"device_id\":\"test-001\",\"sensor_type\":\"temperature\",\"value\":23.5}'"
    query_sensor_data               = "bq query --use_legacy_sql=false 'SELECT * FROM \\`${var.project_id}.${google_bigquery_dataset.smart_city_data.dataset_id}.${google_bigquery_table.sensor_readings.table_id}\\` LIMIT 10'"
    view_function_logs              = "gcloud functions logs read ${google_cloudfunctions_function.sensor_processor.name} --region=${var.region}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    pubsub_topics        = 2  # Main topic + DLQ
    pubsub_subscriptions = 3  # BigQuery + ML + DLQ
    bigquery_tables      = 3  # Readings + Anomalies + Metrics
    cloud_functions      = 1  # Sensor processor
    storage_buckets      = 1  # ML artifacts
    service_accounts     = 1  # IoT sensors
    vertex_ai_datasets   = 1  # ML training data
    monitoring_dashboards = var.dashboard_enabled ? 1 : 0
    alert_policies       = var.alert_policy_enabled ? 2 : 0
    budgets             = var.budget_amount > 0 ? 1 : 0
  }
}