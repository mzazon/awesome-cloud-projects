# Project and resource identification outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Cloud Storage outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for batch processing artifacts"
  value       = google_storage_bucket.feature_pipeline_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.feature_pipeline_bucket.url
}

output "feature_engineering_script_path" {
  description = "Path to the feature engineering script in Cloud Storage"
  value       = "gs://${google_storage_bucket.feature_pipeline_bucket.name}/${google_storage_bucket_object.feature_engineering_script.name}"
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset containing feature tables"
  value       = google_bigquery_dataset.feature_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.feature_dataset.location
}

output "feature_table_id" {
  description = "ID of the BigQuery table containing computed features"
  value       = google_bigquery_table.feature_table.table_id
}

output "feature_table_full_name" {
  description = "Full name of the feature table (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.feature_dataset.dataset_id}.${google_bigquery_table.feature_table.table_id}"
}

output "raw_events_table_id" {
  description = "ID of the BigQuery table containing raw user events"
  value       = google_bigquery_table.raw_events_table.table_id
}

output "raw_events_table_full_name" {
  description = "Full name of the raw events table (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.feature_dataset.dataset_id}.${google_bigquery_table.raw_events_table.table_id}"
}

# Pub/Sub outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for triggering feature updates"
  value       = google_pubsub_topic.feature_updates.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.feature_updates.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for batch job triggering"
  value       = google_pubsub_subscription.feature_pipeline_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.feature_pipeline_subscription.id
}

# Cloud Function outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function for triggering feature pipelines"
  value       = google_cloudfunctions_function.trigger_feature_pipeline.name
}

output "cloud_function_trigger_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions_function.trigger_feature_pipeline.https_trigger_url
}

output "cloud_function_source_archive" {
  description = "Cloud Storage path to the function source archive"
  value       = "gs://${google_storage_bucket.feature_pipeline_bucket.name}/${google_storage_bucket_object.function_source.name}"
}

# Vertex AI Feature Store outputs
output "vertex_ai_feature_group_name" {
  description = "Name of the Vertex AI Feature Group"
  value       = google_vertex_ai_feature_group.user_feature_group.name
}

output "vertex_ai_feature_group_id" {
  description = "Full resource ID of the Vertex AI Feature Group"
  value       = google_vertex_ai_feature_group.user_feature_group.id
}

output "vertex_ai_online_store_name" {
  description = "Name of the Vertex AI Online Store"
  value       = google_vertex_ai_feature_online_store.user_features_store.name
}

output "vertex_ai_online_store_id" {
  description = "Full resource ID of the Vertex AI Online Store"
  value       = google_vertex_ai_feature_online_store.user_features_store.id
}

output "vertex_ai_feature_view_name" {
  description = "Name of the Vertex AI Feature View"
  value       = google_vertex_ai_feature_online_store_feature_view.user_feature_view.name
}

output "vertex_ai_feature_view_id" {
  description = "Full resource ID of the Vertex AI Feature View"
  value       = google_vertex_ai_feature_online_store_feature_view.user_feature_view.id
}

# Feature definitions outputs
output "vertex_ai_features" {
  description = "Map of created Vertex AI features with their resource IDs"
  value = {
    avg_session_duration      = google_vertex_ai_feature.avg_session_duration.id
    total_purchases          = google_vertex_ai_feature.total_purchases.id
    engagement_score         = google_vertex_ai_feature.engagement_score.id
    purchase_frequency_per_day = google_vertex_ai_feature.purchase_frequency_per_day.id
  }
}

# Service Account outputs (when created)
output "batch_service_account_email" {
  description = "Email address of the service account for Cloud Batch jobs"
  value       = var.create_service_accounts ? google_service_account.batch_service_account[0].email : null
}

output "function_service_account_email" {
  description = "Email address of the service account for Cloud Function"
  value       = var.create_service_accounts ? google_service_account.function_service_account[0].email : null
}

# Useful commands and integration outputs
output "bigquery_feature_query_command" {
  description = "Command to query the feature table using bq CLI"
  value       = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.feature_dataset.dataset_id}.${google_bigquery_table.feature_table.table_id}` LIMIT 10'"
}

output "pubsub_publish_command" {
  description = "Command to publish a test message to trigger the feature pipeline"
  value       = "gcloud pubsub topics publish ${google_pubsub_topic.feature_updates.name} --message='{\"event\": \"feature_update_request\", \"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}'"
}

output "vertex_ai_feature_group_describe_command" {
  description = "Command to describe the Vertex AI Feature Group"
  value       = "gcloud ai feature-groups describe ${google_vertex_ai_feature_group.user_feature_group.name} --region=${var.region}"
}

output "cloud_function_logs_command" {
  description = "Command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions_function.trigger_feature_pipeline.name} --region=${var.region} --limit=50"
}

# Cost estimation and monitoring outputs
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the deployed resources (approximate)"
  value = {
    description = "Cost estimates based on moderate usage patterns"
    bigquery    = "BigQuery: $20-50/month (depends on query volume and data size)"
    storage     = "Cloud Storage: $5-15/month (depends on data volume and access patterns)"
    pubsub      = "Pub/Sub: $1-5/month (depends on message volume)"
    functions   = "Cloud Functions: $1-10/month (depends on invocation frequency)"
    vertex_ai   = "Vertex AI Feature Store: $10-30/month (depends on feature serving volume)"
    total_range = "$37-110/month"
    note        = "Actual costs may vary significantly based on usage patterns, data volume, and regional pricing"
  }
}

# Validation and testing outputs
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    check_bigquery_dataset = "bq ls --project_id=${var.project_id} ${google_bigquery_dataset.feature_dataset.dataset_id}"
    check_storage_bucket   = "gsutil ls gs://${google_storage_bucket.feature_pipeline_bucket.name}/"
    check_pubsub_topic     = "gcloud pubsub topics describe ${google_pubsub_topic.feature_updates.name}"
    check_cloud_function   = "gcloud functions describe ${google_cloudfunctions_function.trigger_feature_pipeline.name} --region=${var.region}"
    check_feature_group    = "gcloud ai feature-groups list --region=${var.region} --filter='name:${google_vertex_ai_feature_group.user_feature_group.name}'"
  }
}

# Resource cleanup commands
output "cleanup_commands" {
  description = "Commands to manually clean up resources if needed"
  value = {
    note                = "These commands will permanently delete resources. Use with caution."
    delete_function     = "gcloud functions delete ${google_cloudfunctions_function.trigger_feature_pipeline.name} --region=${var.region} --quiet"
    delete_feature_view = "gcloud ai feature-views delete ${google_vertex_ai_feature_online_store_feature_view.user_feature_view.name} --online-store=${google_vertex_ai_feature_online_store.user_features_store.name} --region=${var.region} --quiet"
    delete_online_store = "gcloud ai online-stores delete ${google_vertex_ai_feature_online_store.user_features_store.name} --region=${var.region} --quiet"
    delete_feature_group = "gcloud ai feature-groups delete ${google_vertex_ai_feature_group.user_feature_group.name} --region=${var.region} --quiet"
    delete_pubsub       = "gcloud pubsub subscriptions delete ${google_pubsub_subscription.feature_pipeline_subscription.name} && gcloud pubsub topics delete ${google_pubsub_topic.feature_updates.name}"
    delete_bigquery     = "bq rm -r -f ${var.project_id}:${google_bigquery_dataset.feature_dataset.dataset_id}"
    delete_storage      = "gsutil -m rm -r gs://${google_storage_bucket.feature_pipeline_bucket.name}"
  }
}

# Integration guidance outputs
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_load_sample_data" = "Load sample data into the raw_user_events table: bq load --source_format=CSV ${var.project_id}:${google_bigquery_dataset.feature_dataset.dataset_id}.${google_bigquery_table.raw_events_table.table_id} sample_data.csv"
    "2_trigger_pipeline" = "Trigger the feature pipeline: ${output.pubsub_publish_command.value}"
    "3_verify_features"  = "Check computed features: ${output.bigquery_feature_query_command.value}"
    "4_monitor_function" = "Monitor function execution: ${output.cloud_function_logs_command.value}"
    "5_access_features"  = "Access features via Vertex AI Feature Store API for real-time serving"
    "6_setup_monitoring" = "Configure Cloud Monitoring alerts for pipeline failures and feature freshness"
  }
}

# Security and compliance outputs
output "security_considerations" {
  description = "Important security and compliance considerations"
  value = {
    service_accounts    = "Dedicated service accounts created with least-privilege access"
    data_encryption     = "Data encrypted at rest in BigQuery and Cloud Storage"
    network_security    = "Consider VPC Service Controls for additional network isolation"
    audit_logging       = "Enable Cloud Audit Logs for compliance and security monitoring"
    data_governance     = "Implement data lineage tracking and feature monitoring"
    access_control      = "Review and restrict IAM permissions based on organizational needs"
  }
}