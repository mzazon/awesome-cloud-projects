# Outputs for Carbon-Efficient Batch Processing Infrastructure
# Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence

# Project Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone for compute resources"
  value       = var.zone
}

# Resource Naming
output "resource_prefix" {
  description = "The generated resource prefix used for all resources"
  value       = local.resource_prefix
}

# Storage Resources
output "carbon_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for carbon data and job artifacts"
  value       = google_storage_bucket.carbon_data_bucket.name
}

output "carbon_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for carbon data"
  value       = google_storage_bucket.carbon_data_bucket.url
}

output "carbon_data_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.carbon_data_bucket.self_link
}

# Pub/Sub Resources
output "carbon_events_topic_name" {
  description = "Name of the Pub/Sub topic for carbon optimization events"
  value       = google_pubsub_topic.carbon_events.name
}

output "carbon_events_topic_id" {
  description = "ID of the Pub/Sub topic for carbon events"
  value       = google_pubsub_topic.carbon_events.id
}

output "carbon_events_subscription_name" {
  description = "Name of the Pub/Sub subscription for carbon event processing"
  value       = google_pubsub_subscription.carbon_events_sub.name
}

output "carbon_events_subscription_id" {
  description = "ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.carbon_events_sub.id
}

output "carbon_events_dlq_topic_name" {
  description = "Name of the dead letter queue topic for failed carbon events"
  value       = google_pubsub_topic.carbon_events_dlq.name
}

# Service Accounts
output "carbon_batch_service_account_email" {
  description = "Email of the service account for carbon-aware batch jobs"
  value       = google_service_account.carbon_batch_sa.email
}

output "carbon_batch_service_account_id" {
  description = "ID of the carbon batch service account"
  value       = google_service_account.carbon_batch_sa.id
}

output "carbon_scheduler_service_account_email" {
  description = "Email of the service account for carbon scheduler function"
  value       = google_service_account.carbon_scheduler_sa.email
}

output "carbon_scheduler_service_account_id" {
  description = "ID of the carbon scheduler service account"
  value       = google_service_account.carbon_scheduler_sa.id
}

# Cloud Functions
output "carbon_scheduler_function_name" {
  description = "Name of the carbon-aware scheduler Cloud Function"
  value       = google_cloudfunctions_function.carbon_scheduler.name
}

output "carbon_scheduler_function_url" {
  description = "HTTPS trigger URL for the carbon scheduler function"
  value       = google_cloudfunctions_function.carbon_scheduler.https_trigger_url
  sensitive   = true
}

output "carbon_scheduler_function_id" {
  description = "ID of the carbon scheduler function"
  value       = google_cloudfunctions_function.carbon_scheduler.id
}

# Security Resources
output "carbon_kms_keyring_name" {
  description = "Name of the KMS key ring for carbon data encryption"
  value       = google_kms_key_ring.carbon_keyring.name
}

output "carbon_kms_key_name" {
  description = "Name of the KMS crypto key for carbon data"
  value       = google_kms_crypto_key.carbon_data_key.name
}

output "carbon_kms_key_id" {
  description = "ID of the KMS crypto key"
  value       = google_kms_crypto_key.carbon_data_key.id
}

# Monitoring Resources
output "carbon_monitoring_service_id" {
  description = "ID of the custom monitoring service for carbon tracking"
  value       = var.enable_carbon_monitoring ? google_monitoring_custom_service.carbon_monitoring[0].service_id : null
}

output "carbon_alert_policy_id" {
  description = "ID of the carbon impact alert policy"
  value       = var.enable_carbon_monitoring ? google_monitoring_alert_policy.high_carbon_impact[0].id : null
}

# Logging Resources
output "carbon_log_sink_name" {
  description = "Name of the log sink for carbon efficiency analysis"
  value       = google_logging_project_sink.carbon_logs.name
}

output "carbon_log_sink_writer_identity" {
  description = "Writer identity for the carbon logs sink"
  value       = google_logging_project_sink.carbon_logs.writer_identity
  sensitive   = true
}

# Scheduling Resources
output "carbon_optimizer_scheduler_name" {
  description = "Name of the Cloud Scheduler job for periodic carbon optimization"
  value       = google_cloud_scheduler_job.carbon_optimizer.name
}

output "carbon_optimizer_scheduler_id" {
  description = "ID of the carbon optimizer scheduler job"
  value       = google_cloud_scheduler_job.carbon_optimizer.id
}

# Configuration Values
output "carbon_configuration" {
  description = "Carbon intelligence configuration parameters"
  value = {
    carbon_intensity_threshold = var.carbon_intensity_threshold
    cfe_percentage_threshold   = var.cfe_percentage_threshold
    batch_parallelism         = var.batch_job_parallelism
    machine_type              = var.batch_machine_type
    use_preemptible           = var.use_preemptible_instances
    monitoring_enabled        = var.enable_carbon_monitoring
  }
}

# Environment Information
output "environment_details" {
  description = "Environment and deployment details"
  value = {
    environment       = var.environment
    deployment_region = var.region
    storage_class     = var.storage_class
    labels           = local.common_labels
  }
}

# CLI Commands for Testing
output "testing_commands" {
  description = "CLI commands for testing the carbon-efficient batch processing infrastructure"
  value = {
    test_scheduler_function = "curl -X POST ${google_cloudfunctions_function.carbon_scheduler.https_trigger_url} -H 'Content-Type: application/json' -d '{\"project_id\": \"${var.project_id}\", \"topic_name\": \"${google_pubsub_topic.carbon_events.name}\"}'"
    
    list_pubsub_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.carbon_events_sub.name} --max-messages=5 --format='value(message.data)' | base64 -d"
    
    check_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.carbon_data_bucket.name}/"
    
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.carbon_scheduler.name} --region=${var.region} --limit=20"
    
    submit_batch_job = "gcloud batch jobs submit carbon-test-job --location=${var.region} --config=batch_job_config.json"
    
    monitor_carbon_metrics = "gcloud monitoring time-series list --filter='metric.type=\"custom.googleapis.com/batch/carbon_impact\"' --interval-start-time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --interval-end-time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "Google Cloud Console URLs for accessing created resources"
  value = {
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.carbon_data_bucket.name}?project=${var.project_id}"
    
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.carbon_events.name}?project=${var.project_id}"
    
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.carbon_scheduler.name}?project=${var.project_id}"
    
    batch_console = "https://console.cloud.google.com/batch?project=${var.project_id}"
    
    monitoring_dashboard = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    
    cloud_scheduler = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
  }
}

# Next Steps Instructions
output "next_steps" {
  description = "Next steps for deploying and testing carbon-efficient batch processing"
  value = [
    "1. Create the function source files in the functions/ directory",
    "2. Create the batch job script in the scripts/ directory", 
    "3. Run 'terraform apply' to deploy the infrastructure",
    "4. Test the carbon scheduler function using the provided curl command",
    "5. Submit a test batch job to validate carbon-aware processing",
    "6. Monitor carbon metrics in Cloud Monitoring console",
    "7. Review carbon efficiency reports in Cloud Storage bucket",
    "8. Set up additional alerting rules for sustainability governance"
  ]
}