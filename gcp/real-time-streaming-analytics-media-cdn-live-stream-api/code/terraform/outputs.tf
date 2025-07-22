# Outputs for GCP Real-Time Streaming Analytics Infrastructure
# These outputs provide essential information for connecting to and using the deployed infrastructure

# Storage and Content Delivery Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for video content"
  value       = google_storage_bucket.streaming_content.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.streaming_content.url
}

output "cdn_ip_address" {
  description = "IP address of the CDN global forwarding rule"
  value       = google_compute_global_forwarding_rule.streaming_forwarding_rule.ip_address
}

output "cdn_url" {
  description = "Base URL for CDN access (use with custom domain)"
  value       = "http://${google_compute_global_forwarding_rule.streaming_forwarding_rule.ip_address}"
}

# Analytics Infrastructure Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.streaming_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.streaming_analytics.location
}

output "streaming_events_table" {
  description = "Full table ID for streaming events table"
  value       = "${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.${google_bigquery_table.streaming_events.table_id}"
}

output "cdn_access_logs_table" {
  description = "Full table ID for CDN access logs table"
  value       = "${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.${google_bigquery_table.cdn_access_logs.table_id}"
}

output "viewer_engagement_view" {
  description = "Full view ID for viewer engagement metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.${google_bigquery_table.viewer_engagement_metrics.table_id}"
}

output "cdn_performance_view" {
  description = "Full view ID for CDN performance metrics"
  value       = "${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.${google_bigquery_table.cdn_performance_metrics.table_id}"
}

# Event Processing Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for streaming events"
  value       = google_pubsub_topic.stream_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.stream_events.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter Pub/Sub topic"
  value       = google_pubsub_topic.dead_letter.name
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for BigQuery"
  value       = google_pubsub_subscription.bq_subscription.name
}

output "cloud_function_name" {
  description = "Name of the Cloud Function for event processing"
  value       = google_cloudfunctions2_function.stream_processor.name
}

output "cloud_function_url" {
  description = "URL of the Cloud Function"
  value       = google_cloudfunctions2_function.stream_processor.service_config[0].uri
}

# Security and Access Outputs
output "service_account_email" {
  description = "Email of the service account for streaming analytics"
  value       = google_service_account.streaming_analytics.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.streaming_analytics.unique_id
}

# Live Streaming Configuration (Reference)
output "live_stream_input_instructions" {
  description = "Instructions for creating Live Stream API resources (not managed by Terraform)"
  value = <<-EOT
    Live Stream API resources must be created using gcloud CLI:
    
    1. Create input endpoint:
       gcloud livestream inputs create live-input-${local.suffix} \
         --location=${var.region} \
         --type=${var.livestream_input_type} \
         --tier=${var.livestream_tier}
    
    2. Create channel configuration file and deploy:
       gcloud livestream channels create live-channel-${local.suffix} \
         --location=${var.region} \
         --config-file=channel-config.yaml
    
    3. Start the channel:
       gcloud livestream channels start live-channel-${local.suffix} \
         --location=${var.region}
    
    Configure the channel to output to: gs://${google_storage_bucket.streaming_content.name}/live-stream/
  EOT
}

# Resource Identifiers for External Integration
output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region for resources"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.suffix
}

# Analytics Query Examples
output "sample_bigquery_queries" {
  description = "Sample BigQuery queries for analytics"
  value = {
    viewer_engagement = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.viewer_engagement_metrics` LIMIT 10"
    cdn_performance   = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.cdn_performance_metrics` LIMIT 10"
    recent_events     = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.streaming_analytics.dataset_id}.streaming_events` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) LIMIT 100"
  }
}

# Event Publishing Example
output "pubsub_publish_command" {
  description = "Example command to publish test events to Pub/Sub"
  value = <<-EOT
    # Publish a test streaming event:
    gcloud pubsub topics publish ${google_pubsub_topic.stream_events.name} \
      --message='{
        "eventType": "stream_start",
        "viewerId": "viewer_123",
        "sessionId": "session_456",
        "streamId": "live-channel-${local.suffix}",
        "quality": "HD",
        "bufferHealth": 0.95,
        "latency": 150,
        "location": "US",
        "userAgent": "TestPlayer/1.0",
        "bitrate": 3000000,
        "resolution": "1280x720",
        "cacheStatus": "HIT",
        "edgeLocation": "${var.region}"
      }'
  EOT
}

# Monitoring and Observability
output "monitoring_dashboard_url" {
  description = "URL template for creating monitoring dashboards"
  value       = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
}

output "logs_explorer_url" {
  description = "URL for viewing Cloud Function logs"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%20resource.labels.function_name%3D%22${google_cloudfunctions2_function.stream_processor.name}%22?project=${var.project_id}"
}

# Cost Management Information
output "cost_optimization_notes" {
  description = "Notes for cost optimization"
  value = <<-EOT
    Cost Optimization Tips:
    1. Storage lifecycle rules are configured to move objects to NEARLINE after ${var.bucket_lifecycle_age_nearline} days
    2. Objects are deleted after ${var.bucket_lifecycle_age_delete} days
    3. BigQuery tables have default expiration of ${var.bigquery_table_expiration_days} days
    4. Cloud Function max instances limited to ${var.function_max_instances}
    5. Pub/Sub message retention set to ${var.pubsub_message_retention_duration}
    
    Monitor your usage at: https://console.cloud.google.com/billing?project=${var.project_id}
  EOT
}

# Security Information
output "security_notes" {
  description = "Security configuration notes"
  value = <<-EOT
    Security Features Enabled:
    1. Uniform bucket-level access: ${var.enable_uniform_bucket_access}
    2. Public access prevention: ${var.enable_public_access_prevention}
    3. Bucket versioning: ${var.enable_bucket_versioning}
    4. Cloud Function ingress: ALLOW_INTERNAL_ONLY
    5. Service account with least privilege roles
    6. IAM-based access control for all resources
    
    Review security settings at: https://console.cloud.google.com/security?project=${var.project_id}
  EOT
}

# Infrastructure Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    test_pubsub = "gcloud pubsub topics publish ${google_pubsub_topic.stream_events.name} --message='test message'"
    check_function = "gcloud functions describe ${google_cloudfunctions2_function.stream_processor.name} --region=${var.region} --gen2"
    verify_bigquery = "bq ls ${google_bigquery_dataset.streaming_analytics.dataset_id}"
    test_storage = "gsutil ls gs://${google_storage_bucket.streaming_content.name}/"
    check_cdn = "curl -I ${google_compute_global_forwarding_rule.streaming_forwarding_rule.ip_address}"
  }
}