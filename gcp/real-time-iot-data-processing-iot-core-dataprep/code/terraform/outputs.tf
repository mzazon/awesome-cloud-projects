# Output Values for IoT Data Processing Pipeline
# This file defines output values that provide important information
# about the deployed infrastructure for verification and integration

# Project and Environment Information
output "project_id" {
  description = "Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name used for resource deployment"
  value       = var.environment
}

# IoT Core Resources
output "iot_registry_id" {
  description = "Full resource ID of the IoT Core device registry"
  value       = google_cloudiot_registry.iot_registry.id
}

output "iot_registry_name" {
  description = "Name of the IoT Core device registry"
  value       = google_cloudiot_registry.iot_registry.name
}

output "iot_device_name" {
  description = "Name of the IoT device"
  value       = google_cloudiot_device.iot_device.name
}

output "device_certificate" {
  description = "Device certificate for IoT authentication (PEM format)"
  value       = tls_self_signed_cert.device_cert.cert_pem
  sensitive   = true
}

output "device_private_key" {
  description = "Device private key for IoT authentication (PEM format)"
  value       = tls_private_key.device_key.private_key_pem
  sensitive   = true
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for IoT telemetry"
  value       = google_pubsub_topic.iot_telemetry.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.iot_telemetry.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.iot_data_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.iot_data_subscription.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

output "schema_name" {
  description = "Name of the Pub/Sub schema for IoT telemetry validation"
  value       = google_pubsub_schema.iot_telemetry_schema.name
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for IoT analytics"
  value       = google_bigquery_dataset.iot_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.iot_analytics.location
}

output "bigquery_table_id" {
  description = "ID of the BigQuery table for sensor readings"
  value       = google_bigquery_table.sensor_readings.table_id
}

output "bigquery_table_full_name" {
  description = "Full name of the BigQuery table (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.iot_analytics.dataset_id}.${google_bigquery_table.sensor_readings.table_id}"
}

# Cloud Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for Dataprep staging"
  value       = google_storage_bucket.dataprep_staging.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.dataprep_staging.url
}

output "sample_data_object_name" {
  description = "Name of the sample data object in the storage bucket"
  value       = google_storage_bucket_object.sample_data.name
}

output "sample_data_url" {
  description = "URL of the sample data object for Dataprep configuration"
  value       = "gs://${google_storage_bucket.dataprep_staging.name}/${google_storage_bucket_object.sample_data.name}"
}

# Service Account and Security
output "dataprep_service_account_email" {
  description = "Email address of the Dataprep service account"
  value       = google_service_account.dataprep_sa.email
}

output "dataprep_service_account_id" {
  description = "ID of the Dataprep service account"
  value       = google_service_account.dataprep_sa.id
}

output "kms_key_ring_name" {
  description = "Name of the KMS key ring for encryption"
  value       = google_kms_key_ring.iot_keyring.name
}

output "kms_crypto_key_name" {
  description = "Name of the KMS crypto key for Dataprep encryption"
  value       = google_kms_crypto_key.dataprep_key.name
}

output "kms_crypto_key_id" {
  description = "Full resource ID of the KMS crypto key"
  value       = google_kms_crypto_key.dataprep_key.id
}

# Monitoring Resources
output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.iot_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the alert policy for low throughput monitoring"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.low_throughput_alert[0].display_name : null
}

# Connection and Integration Information
output "mqtt_bridge_hostname" {
  description = "Hostname for MQTT connections to Cloud IoT Core"
  value       = "mqtt.googleapis.com"
}

output "mqtt_bridge_port" {
  description = "Port number for MQTT connections to Cloud IoT Core"
  value       = 8883
}

output "iot_core_http_endpoint" {
  description = "HTTP endpoint for IoT Core device communication"
  value       = "https://cloudiot.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/registries/${google_cloudiot_registry.iot_registry.name}/devices/${google_cloudiot_device.iot_device.name}:publishEvent"
}

# Dataprep Configuration URLs
output "dataprep_console_url" {
  description = "URL to access Cloud Dataprep console"
  value       = "https://console.cloud.google.com/dataprep?project=${var.project_id}"
}

output "bigquery_console_url" {
  description = "URL to access BigQuery console for the analytics dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.iot_analytics.dataset_id}"
}

# Resource Identifiers for Scripting
output "resource_names" {
  description = "Map of all created resource names for scripting and automation"
  value = {
    iot_registry_name       = google_cloudiot_registry.iot_registry.name
    iot_device_name         = google_cloudiot_device.iot_device.name
    pubsub_topic_name       = google_pubsub_topic.iot_telemetry.name
    pubsub_subscription_name = google_pubsub_subscription.iot_data_subscription.name
    dead_letter_topic_name  = google_pubsub_topic.dead_letter.name
    bigquery_dataset_id     = google_bigquery_dataset.iot_analytics.dataset_id
    bigquery_table_id       = google_bigquery_table.sensor_readings.table_id
    storage_bucket_name     = google_storage_bucket.dataprep_staging.name
    service_account_email   = google_service_account.dataprep_sa.email
    kms_key_ring_name       = google_kms_key_ring.iot_keyring.name
    kms_crypto_key_name     = google_kms_crypto_key.dataprep_key.name
  }
}

# Verification Commands
output "verification_commands" {
  description = "Useful commands for verifying the deployed infrastructure"
  value = {
    check_apis = "gcloud services list --enabled --filter=\"name:(cloudiot.googleapis.com OR pubsub.googleapis.com OR bigquery.googleapis.com OR dataprep.googleapis.com)\""
    check_iot_registry = "gcloud iot registries describe ${google_cloudiot_registry.iot_registry.name} --region=${var.region}"
    check_iot_device = "gcloud iot devices describe ${google_cloudiot_device.iot_device.name} --region=${var.region} --registry=${google_cloudiot_registry.iot_registry.name}"
    check_pubsub_topic = "gcloud pubsub topics describe ${google_pubsub_topic.iot_telemetry.name}"
    check_pubsub_subscription = "gcloud pubsub subscriptions describe ${google_pubsub_subscription.iot_data_subscription.name}"
    check_bigquery_dataset = "bq show ${google_bigquery_dataset.iot_analytics.dataset_id}"
    check_bigquery_table = "bq show ${google_bigquery_dataset.iot_analytics.dataset_id}.${google_bigquery_table.sensor_readings.table_id}"
    check_storage_bucket = "gsutil ls -b gs://${google_storage_bucket.dataprep_staging.name}"
    check_service_account = "gcloud iam service-accounts describe ${google_service_account.dataprep_sa.email}"
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information about potential costs for the deployed resources"
  value = {
    message = "Estimated monthly costs may vary based on usage patterns"
    factors = [
      "Cloud IoT Core: $0.50 per million messages",
      "Pub/Sub: $0.40 per million messages",
      "BigQuery: $5.00 per TB for storage, $5.00 per TB for queries",
      "Cloud Storage: $0.020 per GB for Standard storage",
      "Dataprep: $0.20 per GB processed",
      "Cloud Monitoring: First 150 metrics free, then $0.258 per metric"
    ]
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the IoT data processing pipeline setup"
  value = [
    "1. Open Cloud Dataprep console at: https://console.cloud.google.com/dataprep?project=${var.project_id}",
    "2. Create a new flow and import the sample data file: gs://${google_storage_bucket.dataprep_staging.name}/${google_storage_bucket_object.sample_data.name}",
    "3. Configure data transformations for null handling and outlier detection",
    "4. Set the output destination to BigQuery table: ${var.project_id}.${google_bigquery_dataset.iot_analytics.dataset_id}.${google_bigquery_table.sensor_readings.table_id}",
    "5. Create an IoT device simulator using the provided certificate and private key",
    "6. Start publishing telemetry data to test the complete pipeline",
    "7. Monitor the pipeline using the Cloud Monitoring dashboard"
  ]
}