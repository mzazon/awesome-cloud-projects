# Project and resource identification outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "The suffix used for resource naming"
  value       = local.resource_suffix
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for workforce analytics"
  value       = google_bigquery_dataset.workforce_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.workforce_analytics.location
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.workforce_analytics.dataset_id}!3e1"
}

output "meeting_events_table_id" {
  description = "Full ID of the meeting events table"
  value       = "${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.${google_bigquery_table.meeting_events.table_id}"
}

output "file_events_table_id" {
  description = "Full ID of the file events table"
  value       = "${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.${google_bigquery_table.file_events.table_id}"
}

output "analytics_views" {
  description = "Map of BigQuery analytics views and their full table IDs"
  value = {
    meeting_analytics     = "${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.${google_bigquery_table.meeting_analytics_view.table_id}"
    collaboration_analytics = "${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.${google_bigquery_table.collaboration_analytics_view.table_id}"
    productivity_insights = "${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.${google_bigquery_table.productivity_insights_view.table_id}"
  }
}

# Pub/Sub outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for workspace events"
  value       = google_pubsub_topic.workspace_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.workspace_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for event processing"
  value       = google_pubsub_subscription.events_processor.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.events_processor.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Storage outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for application data"
  value       = google_storage_bucket.workforce_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.workforce_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.workforce_data.self_link
}

# Cloud Run Worker Pool outputs
output "worker_pool_name" {
  description = "Name of the Cloud Run worker pool job"
  value       = google_cloud_run_v2_job.workspace_event_processor.name
}

output "worker_pool_location" {
  description = "Location of the Cloud Run worker pool"
  value       = google_cloud_run_v2_job.workspace_event_processor.location
}

output "worker_pool_url" {
  description = "URL to access the Cloud Run job in the console"
  value       = "https://console.cloud.google.com/run/jobs/details/${var.region}/${google_cloud_run_v2_job.workspace_event_processor.name}?project=${var.project_id}"
}

# Service Account outputs
output "service_account_email" {
  description = "Email of the custom service account (if created)"
  value       = var.create_custom_service_account ? google_service_account.worker_pool_sa[0].email : null
}

output "service_account_id" {
  description = "ID of the custom service account (if created)"
  value       = var.create_custom_service_account ? google_service_account.worker_pool_sa[0].account_id : null
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if created)"
  value       = var.create_monitoring_dashboard ? google_monitoring_dashboard.workforce_analytics[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = var.create_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.workforce_analytics[0].id}?project=${var.project_id}" : null
}

output "alert_policies" {
  description = "Map of created alerting policies and their IDs"
  value = var.create_alerting_policies ? {
    high_processing_latency = google_monitoring_alert_policy.high_processing_latency[0].id
    pubsub_delivery_failures = google_monitoring_alert_policy.pubsub_delivery_failures[0].id
  } : {}
}

# Configuration outputs for application deployment
output "environment_variables" {
  description = "Environment variables to use for the worker pool application"
  value = {
    PROJECT_ID        = var.project_id
    SUBSCRIPTION_NAME = google_pubsub_subscription.events_processor.name
    DATASET_NAME      = google_bigquery_dataset.workforce_analytics.dataset_id
    REGION            = var.region
    ENVIRONMENT       = var.environment
    BUCKET_NAME       = google_storage_bucket.workforce_data.name
  }
}

# Workspace Events API configuration
output "workspace_events_config" {
  description = "Configuration template for Google Workspace Events API subscription"
  value = {
    name = "projects/${var.project_id}/subscriptions/workforce-analytics"
    targetResource = "//workspace.googleapis.com/users/*"
    eventTypes = [
      "google.workspace.calendar.event.v1.created",
      "google.workspace.calendar.event.v1.updated",
      "google.workspace.drive.file.v1.created",
      "google.workspace.drive.file.v1.updated",
      "google.workspace.meet.participant.v1.joined",
      "google.workspace.meet.participant.v1.left",
      "google.workspace.meet.recording.v1.fileGenerated"
    ]
    notificationEndpoint = {
      pubsubTopic = google_pubsub_topic.workspace_events.id
    }
    payloadOptions = {
      includeResource = true
      fieldMask = "eventType,eventTime,resource"
    }
  }
}

# Sample BigQuery queries for analytics
output "sample_queries" {
  description = "Sample BigQuery queries for workforce analytics"
  value = {
    meeting_analytics = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.meeting_analytics` LIMIT 10"
    collaboration_analytics = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.collaboration_analytics` LIMIT 10"
    productivity_insights = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.productivity_insights` LIMIT 10"
    weekly_meeting_summary = "SELECT organizer_email, COUNT(*) as total_meetings, AVG(duration_minutes) as avg_duration FROM `${var.project_id}.${google_bigquery_dataset.workforce_analytics.dataset_id}.meeting_events` WHERE start_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 7 DAY) GROUP BY organizer_email ORDER BY total_meetings DESC"
  }
}

# Container build command
output "container_build_command" {
  description = "Command to build the container image for the worker pool"
  value       = "gcloud builds submit --tag gcr.io/${var.project_id}/workspace-analytics ."
}

# Deployment verification commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_bigquery_dataset = "bq ls ${var.project_id}:${google_bigquery_dataset.workforce_analytics.dataset_id}"
    check_pubsub_topic = "gcloud pubsub topics describe ${google_pubsub_topic.workspace_events.name}"
    check_worker_pool = "gcloud beta run jobs describe ${google_cloud_run_v2_job.workspace_event_processor.name} --region=${var.region}"
    check_storage_bucket = "gsutil ls -b gs://${google_storage_bucket.workforce_data.name}"
    test_pubsub_message = "gcloud pubsub topics publish ${google_pubsub_topic.workspace_events.name} --message='{\"eventId\":\"test-123\",\"eventType\":\"google.workspace.calendar.event.v1.created\"}'"
  }
}

# Cost optimization recommendations
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the workforce analytics infrastructure"
  value = [
    "Consider using BigQuery partitioning and clustering for large datasets",
    "Implement lifecycle policies on Cloud Storage for long-term cost reduction",
    "Monitor Cloud Run worker pool scaling and adjust min/max instances based on usage",
    "Use preemptible instances where possible for batch processing workloads",
    "Set up budget alerts to monitor spending on BigQuery and other services",
    "Review Pub/Sub message retention policies to balance reliability and cost"
  ]
}

# Security recommendations
output "security_recommendations" {
  description = "Security best practices for the workforce analytics system"
  value = [
    "Regularly rotate service account keys and review IAM permissions",
    "Enable VPC Service Controls to secure data access between services",
    "Implement data classification and access controls in BigQuery",
    "Use Cloud KMS for additional encryption of sensitive workspace data",
    "Set up Cloud Security Command Center for comprehensive security monitoring",
    "Regularly audit Workspace Events API permissions and subscriptions"
  ]
}

# Next steps for implementation
output "next_steps" {
  description = "Next steps to complete the workforce analytics implementation"
  value = [
    "1. Configure Google Workspace Events API subscriptions in the Admin Console",
    "2. Build and deploy the container image: ${local.bucket_name}/code/",
    "3. Test the event processing pipeline with sample messages",
    "4. Set up notification channels for monitoring alerts",
    "5. Create additional BigQuery views for specific business metrics",
    "6. Configure data retention policies based on compliance requirements",
    "7. Set up automated reporting and dashboard sharing with stakeholders"
  ]
}