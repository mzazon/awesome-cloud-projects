# Project and Basic Configuration Outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name used for resource naming"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Pub/Sub Resource Outputs
output "pubsub_topic_name" {
  description = "Name of the created Pub/Sub topic for user events"
  value       = google_pubsub_topic.user_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.user_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the created Pub/Sub subscription for analytics processing"
  value       = google_pubsub_subscription.analytics_processor.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.analytics_processor.id
}

output "pubsub_subscription_path" {
  description = "Full path of the Pub/Sub subscription for application configuration"
  value       = "projects/${var.project_id}/subscriptions/${google_pubsub_subscription.analytics_processor.name}"
}

# Firestore Database Outputs
output "firestore_database_name" {
  description = "Name of the created Firestore database"
  value       = google_firestore_database.behavioral_analytics.name
}

output "firestore_database_id" {
  description = "Full resource ID of the Firestore database"
  value       = google_firestore_database.behavioral_analytics.id
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.behavioral_analytics.location_id
}

# Firestore Index Outputs
output "firestore_indexes" {
  description = "List of created Firestore composite indexes"
  value = {
    user_events_by_user_timestamp = {
      name       = google_firestore_index.user_events_by_user_timestamp.name
      collection = google_firestore_index.user_events_by_user_timestamp.collection
      fields     = google_firestore_index.user_events_by_user_timestamp.fields
    }
    user_events_by_type_timestamp = {
      name       = google_firestore_index.user_events_by_type_timestamp.name
      collection = google_firestore_index.user_events_by_type_timestamp.collection
      fields     = google_firestore_index.user_events_by_type_timestamp.fields
    }
    analytics_aggregates_by_period = {
      name       = google_firestore_index.analytics_aggregates_by_period.name
      collection = google_firestore_index.analytics_aggregates_by_period.collection
      fields     = google_firestore_index.analytics_aggregates_by_period.fields
    }
  }
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the created service account for the analytics processor"
  value       = google_service_account.analytics_processor.email
}

output "service_account_id" {
  description = "Full resource ID of the service account"
  value       = google_service_account.analytics_processor.id
}

output "service_account_name" {
  description = "Name of the service account"
  value       = google_service_account.analytics_processor.name
}

# Cloud Run Job Outputs
output "cloud_run_job_name" {
  description = "Name of the created Cloud Run job (worker pool)"
  value       = google_cloud_run_v2_job.behavioral_processor.name
}

output "cloud_run_job_id" {
  description = "Full resource ID of the Cloud Run job"
  value       = google_cloud_run_v2_job.behavioral_processor.id
}

output "cloud_run_job_location" {
  description = "Location of the Cloud Run job"
  value       = google_cloud_run_v2_job.behavioral_processor.location
}

output "cloud_run_job_uri" {
  description = "URI of the Cloud Run job"
  value       = "https://console.cloud.google.com/run/jobs/details/${google_cloud_run_v2_job.behavioral_processor.location}/${google_cloud_run_v2_job.behavioral_processor.name}?project=${var.project_id}"
}

# Artifact Registry Outputs
output "artifact_registry_repository_name" {
  description = "Name of the created Artifact Registry repository"
  value       = google_artifact_registry_repository.behavioral_analytics.repository_id
}

output "artifact_registry_repository_id" {
  description = "Full resource ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.behavioral_analytics.id
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository for pushing container images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.behavioral_analytics.repository_id}"
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the created Cloud Monitoring dashboard"
  value       = var.enable_monitoring_dashboard ? google_monitoring_dashboard.behavioral_analytics[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to view the Cloud Monitoring dashboard"
  value = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.behavioral_analytics[0].id)[3]}?project=${var.project_id}" : null
}

output "alert_policy_ids" {
  description = "IDs of created alert policies"
  value = var.enable_alert_policies ? {
    high_pubsub_lag     = google_monitoring_alert_policy.high_pubsub_lag[0].id
    cloud_run_failures  = google_monitoring_alert_policy.cloud_run_job_failures[0].id
  } : {}
}

# Storage and Logging Outputs
output "log_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for log storage"
  value       = google_storage_bucket.log_storage.name
}

output "log_storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for log storage"
  value       = google_storage_bucket.log_storage.url
}

output "logging_sink_name" {
  description = "Name of the created logging sink"
  value       = google_logging_project_sink.behavioral_analytics_logs.name
}

output "logging_sink_writer_identity" {
  description = "Writer identity of the logging sink"
  value       = google_logging_project_sink.behavioral_analytics_logs.writer_identity
  sensitive   = true
}

# VPC Connector Output (conditional)
output "vpc_connector_name" {
  description = "Name of the VPC connector (if created)"
  value       = var.enable_vpc_connector ? google_vpc_access_connector.behavioral_analytics[0].name : null
}

output "vpc_connector_id" {
  description = "Full resource ID of the VPC connector (if created)"
  value       = var.enable_vpc_connector ? google_vpc_access_connector.behavioral_analytics[0].id : null
}

# Application Configuration Outputs
output "application_environment_variables" {
  description = "Environment variables to set in the application container"
  value = {
    GOOGLE_CLOUD_PROJECT  = var.project_id
    PUBSUB_SUBSCRIPTION   = "projects/${var.project_id}/subscriptions/${google_pubsub_subscription.analytics_processor.name}"
    FIRESTORE_DATABASE    = google_firestore_database.behavioral_analytics.name
    GOOGLE_CLOUD_REGION   = var.region
    ENVIRONMENT           = var.environment
  }
}

# Container Image Build Commands
output "container_build_commands" {
  description = "Commands to build and push the container image to Artifact Registry"
  value = {
    configure_docker = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    build_image     = "gcloud builds submit . --tag=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.behavioral_analytics.repository_id}/processor:latest"
    image_uri       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.behavioral_analytics.repository_id}/processor:latest"
  }
}

# Deployment Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_job_status = "gcloud run jobs describe ${google_cloud_run_v2_job.behavioral_processor.name} --region=${var.region} --format='value(status.conditions[0].status)'"
    view_job_logs   = "gcloud logs read 'resource.type=cloud_run_job AND resource.labels.job_name=${google_cloud_run_v2_job.behavioral_processor.name}' --limit=20"
    list_firestore_collections = "gcloud firestore databases list --filter='name:${google_firestore_database.behavioral_analytics.name}'"
    check_pubsub_subscription = "gcloud pubsub subscriptions describe ${google_pubsub_subscription.analytics_processor.name}"
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation"
  value = {
    cloud_run_job = {
      memory_gb = var.worker_pool_memory
      cpu_count = var.worker_pool_cpu
      min_instances = var.worker_pool_min_instances
      max_instances = var.worker_pool_max_instances
    }
    pubsub = {
      topic_name = google_pubsub_topic.user_events.name
      message_retention = var.message_retention_duration
    }
    firestore = {
      database_name = google_firestore_database.behavioral_analytics.name
      location = google_firestore_database.behavioral_analytics.location_id
    }
    storage = {
      log_bucket = google_storage_bucket.log_storage.name
      location = google_storage_bucket.log_storage.location
    }
  }
}

# Summary Output
output "deployment_summary" {
  description = "Summary of the deployed behavioral analytics infrastructure"
  value = {
    project_id = var.project_id
    region = var.region
    environment = var.environment
    
    # Core components
    pubsub_topic = google_pubsub_topic.user_events.name
    pubsub_subscription = google_pubsub_subscription.analytics_processor.name
    firestore_database = google_firestore_database.behavioral_analytics.name
    cloud_run_job = google_cloud_run_v2_job.behavioral_processor.name
    service_account = google_service_account.analytics_processor.email
    
    # Container registry
    artifact_registry_repo = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.behavioral_analytics.repository_id}"
    
    # Monitoring
    monitoring_dashboard_enabled = var.enable_monitoring_dashboard
    alert_policies_enabled = var.enable_alert_policies
    
    # Next steps
    next_steps = [
      "1. Build and push your container image to the Artifact Registry repository",
      "2. Update the Cloud Run job with your container image URI",
      "3. Execute the Cloud Run job to start processing events",
      "4. Send test events to the Pub/Sub topic",
      "5. Monitor the dashboard and logs for successful processing"
    ]
  }
}