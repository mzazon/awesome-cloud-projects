# ============================================================================
# Infrastructure Outputs for Fraud Detection System
# ============================================================================

# Project and Regional Configuration
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

output "resource_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.resource_suffix
}

# ============================================================================
# Storage Configuration Outputs
# ============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for ML artifacts"
  value       = google_storage_bucket.fraud_detection_bucket.name
}

output "storage_bucket_url" {
  description = "Full URL of the Cloud Storage bucket"
  value       = google_storage_bucket.fraud_detection_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.fraud_detection_bucket.self_link
}

output "training_data_path" {
  description = "Cloud Storage path for training data"
  value       = "gs://${google_storage_bucket.fraud_detection_bucket.name}/training_data/"
}

output "model_artifacts_path" {
  description = "Cloud Storage path for model artifacts"
  value       = "gs://${google_storage_bucket.fraud_detection_bucket.name}/models/"
}

output "dataflow_temp_path" {
  description = "Cloud Storage path for Dataflow temporary files"
  value       = "gs://${google_storage_bucket.fraud_detection_bucket.name}/temp/"
}

output "dataflow_staging_path" {
  description = "Cloud Storage path for Dataflow staging files"
  value       = "gs://${google_storage_bucket.fraud_detection_bucket.name}/staging/"
}

# ============================================================================
# BigQuery Configuration Outputs
# ============================================================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for fraud detection data"
  value       = google_bigquery_dataset.fraud_detection_dataset.dataset_id
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.fraud_detection_dataset.self_link
}

output "transactions_table_id" {
  description = "BigQuery transactions table ID"
  value       = google_bigquery_table.transactions_table.table_id
}

output "fraud_alerts_table_id" {
  description = "BigQuery fraud alerts table ID"
  value       = google_bigquery_table.fraud_alerts_table.table_id
}

output "transactions_table_reference" {
  description = "Full reference to the transactions table for queries"
  value       = "${var.project_id}.${google_bigquery_dataset.fraud_detection_dataset.dataset_id}.${google_bigquery_table.transactions_table.table_id}"
}

output "fraud_alerts_table_reference" {
  description = "Full reference to the fraud alerts table for queries"
  value       = "${var.project_id}.${google_bigquery_dataset.fraud_detection_dataset.dataset_id}.${google_bigquery_table.fraud_alerts_table.table_id}"
}

# ============================================================================
# Pub/Sub Configuration Outputs
# ============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for transaction streams"
  value       = google_pubsub_topic.transaction_stream.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.transaction_stream.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for processing"
  value       = google_pubsub_subscription.fraud_processor.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.fraud_processor.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic"
  value       = google_pubsub_topic.dead_letter_topic.name
}

output "transaction_schema_id" {
  description = "ID of the transaction schema"
  value       = google_pubsub_schema.transaction_schema.id
}

# ============================================================================
# Vertex AI Configuration Outputs
# ============================================================================

output "vertex_ai_dataset_id" {
  description = "Vertex AI dataset ID for fraud detection"
  value       = google_vertex_ai_dataset.fraud_detection_dataset.id
}

output "vertex_ai_dataset_name" {
  description = "Vertex AI dataset name"
  value       = google_vertex_ai_dataset.fraud_detection_dataset.name
}

output "vertex_ai_endpoint_id" {
  description = "Vertex AI endpoint ID for model serving"
  value       = google_vertex_ai_endpoint.fraud_detection_endpoint.id
}

output "vertex_ai_endpoint_name" {
  description = "Vertex AI endpoint name"
  value       = google_vertex_ai_endpoint.fraud_detection_endpoint.name
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = var.vertex_ai_region
}

# ============================================================================
# Service Account Outputs
# ============================================================================

output "dataflow_service_account_email" {
  description = "Email of the Dataflow service account"
  value       = var.create_service_accounts ? google_service_account.dataflow_service_account[0].email : "default"
}

output "vertex_ai_service_account_email" {
  description = "Email of the Vertex AI service account"
  value       = var.create_service_accounts ? google_service_account.vertex_ai_service_account[0].email : "default"
}

output "bigquery_service_account_email" {
  description = "Email of the BigQuery service account"
  value       = var.create_service_accounts ? google_service_account.bigquery_service_account[0].email : "default"
}

# ============================================================================
# Security and Encryption Outputs
# ============================================================================

output "kms_keyring_id" {
  description = "ID of the KMS keyring (if created)"
  value       = var.enable_cost_optimization ? null : (length(google_kms_key_ring.fraud_detection_keyring) > 0 ? google_kms_key_ring.fraud_detection_keyring[0].id : null)
}

output "vertex_ai_kms_key_id" {
  description = "ID of the Vertex AI KMS key (if created)"
  value       = var.enable_cost_optimization ? null : (length(google_kms_crypto_key.vertex_ai_key) > 0 ? google_kms_crypto_key.vertex_ai_key[0].id : null)
}

# ============================================================================
# Monitoring Configuration Outputs
# ============================================================================

output "fraud_detection_metric_name" {
  description = "Name of the fraud detection rate metric"
  value       = var.enable_monitoring ? google_logging_metric.fraud_detection_rate[0].name : null
}

output "transaction_processing_metric_name" {
  description = "Name of the transaction processing rate metric"
  value       = var.enable_monitoring ? google_logging_metric.transaction_processing_rate[0].name : null
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if created)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : null
}

output "high_fraud_rate_alert_policy_id" {
  description = "ID of the high fraud rate alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_fraud_rate[0].name : null
}

output "processing_lag_alert_policy_id" {
  description = "ID of the processing lag alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.processing_lag[0].name : null
}

# ============================================================================
# Dataflow Configuration Outputs
# ============================================================================

output "dataflow_configuration" {
  description = "Configuration parameters for Dataflow pipeline deployment"
  value = {
    project_id          = var.project_id
    region              = var.region
    job_name            = var.dataflow_job_name
    temp_location       = "gs://${google_storage_bucket.fraud_detection_bucket.name}/temp/"
    staging_location    = "gs://${google_storage_bucket.fraud_detection_bucket.name}/staging/"
    max_workers         = var.dataflow_max_workers
    machine_type        = var.dataflow_machine_type
    service_account     = var.create_service_accounts ? google_service_account.dataflow_service_account[0].email : null
    subnetwork         = null # Can be customized for VPC deployment
    use_public_ips     = true # Can be set to false for private Google Access
  }
}

# ============================================================================
# API Configuration Outputs
# ============================================================================

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.required_apis
}

# ============================================================================
# CLI Command Outputs for Easy Access
# ============================================================================

output "gcloud_commands" {
  description = "Useful gcloud commands for interacting with the infrastructure"
  value = {
    # BigQuery commands
    list_datasets         = "gcloud alpha bq datasets list --project=${var.project_id}"
    query_transactions    = "bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `${var.project_id}.${google_bigquery_dataset.fraud_detection_dataset.dataset_id}.${google_bigquery_table.transactions_table.table_id}`'"
    query_fraud_alerts    = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.fraud_detection_dataset.dataset_id}.${google_bigquery_table.fraud_alerts_table.table_id}` ORDER BY alert_timestamp DESC LIMIT 10'"
    
    # Pub/Sub commands
    list_topics           = "gcloud pubsub topics list --project=${var.project_id}"
    list_subscriptions    = "gcloud pubsub subscriptions list --project=${var.project_id}"
    publish_test_message  = "gcloud pubsub topics publish ${google_pubsub_topic.transaction_stream.name} --message='{\"transaction_id\":\"test-001\",\"user_id\":\"user_123\",\"amount\":100.0,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}'"
    
    # Storage commands
    list_bucket_contents  = "gsutil ls -r gs://${google_storage_bucket.fraud_detection_bucket.name}/"
    
    # Vertex AI commands
    list_datasets         = "gcloud ai datasets list --region=${var.vertex_ai_region} --project=${var.project_id}"
    list_endpoints        = "gcloud ai endpoints list --region=${var.vertex_ai_region} --project=${var.project_id}"
    
    # Monitoring commands
    list_metrics          = "gcloud logging metrics list --project=${var.project_id}"
    list_alert_policies   = "gcloud alpha monitoring policies list --project=${var.project_id}"
  }
}

# ============================================================================
# Web Console URLs for Easy Access
# ============================================================================

output "console_urls" {
  description = "Google Cloud Console URLs for easy access to resources"
  value = {
    bigquery_dataset     = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.fraud_detection_dataset.dataset_id}"
    pubsub_topics        = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
    storage_bucket       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.fraud_detection_bucket.name}?project=${var.project_id}"
    vertex_ai_datasets   = "https://console.cloud.google.com/vertex-ai/datasets?project=${var.project_id}"
    vertex_ai_endpoints  = "https://console.cloud.google.com/vertex-ai/endpoints?project=${var.project_id}"
    dataflow_jobs        = "https://console.cloud.google.com/dataflow/jobs?project=${var.project_id}&region=${var.region}"
    monitoring_overview  = "https://console.cloud.google.com/monitoring/overview?project=${var.project_id}"
    logging_explorer     = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# ============================================================================
# Summary Information
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed fraud detection infrastructure"
  value = {
    infrastructure_type = "Real-Time Fraud Detection System"
    primary_services = [
      "Vertex AI",
      "Cloud Dataflow", 
      "Cloud Pub/Sub",
      "BigQuery"
    ]
    deployment_environment = var.environment
    estimated_monthly_cost = "See Google Cloud Pricing Calculator for current rates"
    key_features = [
      "Real-time transaction processing",
      "ML-based fraud detection",
      "Scalable streaming analytics",
      "Comprehensive monitoring and alerting",
      "Enterprise-grade security"
    ]
    next_steps = [
      "Upload training data to Cloud Storage",
      "Train fraud detection model with Vertex AI AutoML",
      "Deploy trained model to Vertex AI endpoint",
      "Start Dataflow pipeline for real-time processing",
      "Test with transaction simulator",
      "Configure fraud investigation workflows"
    ]
  }
}