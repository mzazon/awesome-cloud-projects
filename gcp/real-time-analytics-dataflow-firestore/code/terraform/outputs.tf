# Outputs for real-time analytics platform deployment
# These outputs provide essential information for accessing and managing the deployed resources

# Project and Region Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources are deployed"
  value       = var.zone
}

output "resource_suffix" {
  description = "Unique suffix appended to resource names"
  value       = random_id.suffix.hex
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for event ingestion"
  value       = google_pubsub_topic.events_topic.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.events_topic.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for the Dataflow pipeline"
  value       = google_pubsub_subscription.events_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.events_subscription.id
}

# Cloud Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for data archival"
  value       = google_storage_bucket.analytics_archive.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for data archival"
  value       = google_storage_bucket.analytics_archive.url
}

output "storage_bucket_self_link" {
  description = "Self link of the Cloud Storage bucket"
  value       = google_storage_bucket.analytics_archive.self_link
}

output "temp_location" {
  description = "Temporary location for Dataflow pipeline operations"
  value       = local.temp_location
}

output "staging_location" {
  description = "Staging location for Dataflow pipeline operations"
  value       = local.staging_location
}

# Firestore Resources
output "firestore_database_name" {
  description = "Name of the Firestore database for real-time analytics"
  value       = google_firestore_database.analytics_database.name
}

output "firestore_database_id" {
  description = "ID of the Firestore database"
  value       = google_firestore_database.analytics_database.id
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.analytics_database.location_id
}

output "app_engine_application_id" {
  description = "ID of the App Engine application (required for Firestore)"
  value       = google_app_engine_application.app.app_id
}

# Service Account Information
output "dataflow_service_account_email" {
  description = "Email address of the Dataflow service account"
  value       = google_service_account.dataflow_service_account.email
}

output "dataflow_service_account_id" {
  description = "Unique ID of the Dataflow service account"
  value       = google_service_account.dataflow_service_account.unique_id
}

output "dataflow_service_account_name" {
  description = "Name of the Dataflow service account"
  value       = google_service_account.dataflow_service_account.name
}

# Pipeline Configuration
output "dataflow_job_name" {
  description = "Suggested name for the Dataflow streaming job"
  value       = local.dataflow_job_name
}

output "pipeline_code_location" {
  description = "Location of the uploaded pipeline code in Cloud Storage"
  value       = "gs://${google_storage_bucket.analytics_archive.name}/pipeline/streaming_analytics.py"
}

output "pipeline_requirements_location" {
  description = "Location of the pipeline requirements file in Cloud Storage"
  value       = "gs://${google_storage_bucket.analytics_archive.name}/pipeline/requirements.txt"
}

output "event_generator_location" {
  description = "Location of the event generator script in Cloud Storage"
  value       = "gs://${google_storage_bucket.analytics_archive.name}/scripts/generate_events.py"
}

# Firestore Index Information
output "firestore_analytics_metrics_index_name" {
  description = "Name of the Firestore index for analytics_metrics collection"
  value       = google_firestore_index.analytics_metrics_index.name
}

output "firestore_user_sessions_index_name" {
  description = "Name of the Firestore index for user_sessions collection"
  value       = google_firestore_index.user_sessions_index.name
}

# Connection and Configuration Information
output "pubsub_publish_command" {
  description = "Example command to publish test events to the Pub/Sub topic"
  value = <<EOT
gcloud pubsub topics publish ${google_pubsub_topic.events_topic.name} \
  --message='{"event_type":"test","user_id":"user_001","timestamp":"${formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())}","properties":{"page":"/test","device":"desktop"}}' \
  --project=${var.project_id}
EOT
}

output "dataflow_deploy_command" {
  description = "Command to deploy the Dataflow streaming pipeline"
  value = <<EOT
python streaming_analytics.py \
  --runner=DataflowRunner \
  --project=${var.project_id} \
  --region=${var.region} \
  --temp_location=${local.temp_location} \
  --staging_location=${local.staging_location} \
  --job_name=${local.dataflow_job_name} \
  --subscription=${google_pubsub_subscription.events_subscription.name} \
  --bucket=${google_storage_bucket.analytics_archive.name} \
  --service_account_email=${google_service_account.dataflow_service_account.email} \
  --use_public_ips=${var.dataflow_use_public_ips ? "true" : "false"} \
  --max_num_workers=${var.dataflow_max_workers} \
  --streaming
EOT
}

output "firestore_query_examples" {
  description = "Example queries for accessing analytics data in Firestore"
  value = {
    gcloud_query = "gcloud firestore query --collection=analytics_metrics --project=${var.project_id}"
    python_query = <<EOT
from google.cloud import firestore
db = firestore.Client(project='${var.project_id}')
metrics = list(db.collection('analytics_metrics').limit(10).stream())
sessions = list(db.collection('user_sessions').limit(10).stream())
EOT
  }
}

# Environment Variables for Local Development
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    PROJECT_ID            = var.project_id
    REGION               = var.region
    ZONE                 = var.zone
    PUBSUB_TOPIC         = google_pubsub_topic.events_topic.name
    SUBSCRIPTION         = google_pubsub_subscription.events_subscription.name
    STORAGE_BUCKET       = google_storage_bucket.analytics_archive.name
    DATAFLOW_JOB         = local.dataflow_job_name
    SERVICE_ACCOUNT      = google_service_account.dataflow_service_account.email
    FIRESTORE_DATABASE   = google_firestore_database.analytics_database.name
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "Google Cloud Console URLs for accessing deployed resources"
  value = {
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.events_topic.name}?project=${var.project_id}"
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.analytics_archive.name}?project=${var.project_id}"
    firestore_database = "https://console.cloud.google.com/firestore/databases/-default-/data?project=${var.project_id}"
    dataflow_jobs = "https://console.cloud.google.com/dataflow/jobs?project=${var.project_id}&region=${var.region}"
    service_accounts = "https://console.cloud.google.com/iam-admin/serviceaccounts?project=${var.project_id}"
  }
}

# Cost Estimation Information
output "cost_estimation_notes" {
  description = "Important information for estimating costs of the deployed resources"
  value = {
    dataflow_cost = "Dataflow charges based on vCPU-hours and memory-hours. Monitor usage in Cloud Billing."
    pubsub_cost = "Pub/Sub charges per message and throughput. First 10GB per month is free."
    firestore_cost = "Firestore charges for document reads, writes, and deletes. Monitor usage in Cloud Billing."
    storage_cost = "Cloud Storage charges for storage and operations. Lifecycle policies help optimize costs."
    monitoring_tip = "Enable billing alerts and use Cloud Monitoring to track resource usage and costs."
  }
}

# Security and Access Information
output "security_notes" {
  description = "Important security information for the deployed resources"
  value = {
    service_account_principle = "Service account follows principle of least privilege with minimal required permissions"
    firestore_access = "Firestore access is controlled through IAM. Consider Firestore Security Rules for application-level access control"
    network_security = "Dataflow workers can be configured to use private IPs for enhanced security"
    monitoring = "Enable Cloud Logging and Cloud Monitoring for comprehensive security monitoring"
  }
}