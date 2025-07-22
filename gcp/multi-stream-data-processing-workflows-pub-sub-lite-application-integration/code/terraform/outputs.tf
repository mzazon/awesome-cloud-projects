# Outputs for Multi-Stream Data Processing Workflows
# These outputs provide essential information for connecting to and managing
# the deployed infrastructure components

# Project and location information
output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Primary region for resource deployment"
  value       = var.region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Pub/Sub Lite resource information
output "pubsub_lite_reservation_name" {
  description = "Name of the Pub/Sub Lite throughput reservation"
  value       = google_pubsub_lite_reservation.reservation.name
}

output "pubsub_lite_reservation_throughput" {
  description = "Total throughput capacity of the Pub/Sub Lite reservation"
  value       = google_pubsub_lite_reservation.reservation.throughput_capacity
}

output "pubsub_lite_topics" {
  description = "Map of Pub/Sub Lite topic names and their configurations"
  value = {
    for key, topic in google_pubsub_lite_topic.topics : key => {
      name        = topic.name
      partitions  = topic.partition_config[0].count
      publish_mib = topic.partition_config[0].capacity[0].publish_mib_per_sec
      subscribe_mib = topic.partition_config[0].capacity[0].subscribe_mib_per_sec
      retention_period = topic.retention_config[0].period
      full_path = "projects/${var.project_id}/locations/${var.region}/topics/${topic.name}"
    }
  }
}

output "pubsub_lite_analytics_subscriptions" {
  description = "Map of Pub/Sub Lite analytics subscription names and paths"
  value = {
    for key, subscription in google_pubsub_lite_subscription.analytics_subscriptions : key => {
      name = subscription.name
      topic = subscription.topic
      delivery_requirement = subscription.delivery_config[0].delivery_requirement
      full_path = "projects/${var.project_id}/locations/${var.region}/subscriptions/${subscription.name}"
    }
  }
}

output "pubsub_lite_workflow_subscriptions" {
  description = "Map of Pub/Sub Lite workflow subscription names and paths"
  value = {
    for key, subscription in google_pubsub_lite_subscription.workflow_subscriptions : key => {
      name = subscription.name
      topic = subscription.topic
      delivery_requirement = subscription.delivery_config[0].delivery_requirement
      full_path = "projects/${var.project_id}/locations/${var.region}/subscriptions/${subscription.name}"
    }
  }
}

# BigQuery resource information
output "bigquery_dataset" {
  description = "BigQuery dataset information"
  value = {
    dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
    project_id = google_bigquery_dataset.analytics_dataset.project
    location   = google_bigquery_dataset.analytics_dataset.location
    full_path  = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}"
    description = google_bigquery_dataset.analytics_dataset.description
  }
}

output "bigquery_tables" {
  description = "BigQuery table information"
  value = {
    iot_sensor_data = {
      table_id = google_bigquery_table.iot_sensor_data.table_id
      full_path = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.iot_sensor_data.table_id}"
      partition_field = google_bigquery_table.iot_sensor_data.time_partitioning[0].field
      clustering_fields = google_bigquery_table.iot_sensor_data.clustering
    }
    application_events = {
      table_id = google_bigquery_table.application_events.table_id
      full_path = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.application_events.table_id}"
      partition_field = google_bigquery_table.application_events.time_partitioning[0].field
      clustering_fields = google_bigquery_table.application_events.clustering
    }
    system_logs_summary = {
      table_id = google_bigquery_table.system_logs_summary.table_id
      full_path = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.${google_bigquery_table.system_logs_summary.table_id}"
      partition_field = google_bigquery_table.system_logs_summary.time_partitioning[0].field
      clustering_fields = google_bigquery_table.system_logs_summary.clustering
    }
  }
}

# Cloud Storage information
output "storage_bucket" {
  description = "Cloud Storage bucket information"
  value = {
    name          = google_storage_bucket.data_lake.name
    url           = google_storage_bucket.data_lake.url
    location      = google_storage_bucket.data_lake.location
    storage_class = google_storage_bucket.data_lake.storage_class
    self_link     = google_storage_bucket.data_lake.self_link
  }
}

output "storage_folder_structure" {
  description = "Cloud Storage folder structure created"
  value = {
    for folder in google_storage_bucket_object.dataflow_folders : folder.name => {
      name = folder.name
      path = "gs://${google_storage_bucket.data_lake.name}/${folder.name}"
    }
  }
}

# Service Account information
output "service_account" {
  description = "Application Integration service account information"
  value = {
    account_id   = google_service_account.app_integration_sa.account_id
    email        = google_service_account.app_integration_sa.email
    display_name = google_service_account.app_integration_sa.display_name
    unique_id    = google_service_account.app_integration_sa.unique_id
  }
}

output "service_account_key" {
  description = "Service account key for external applications (if created)"
  value       = null
  sensitive   = true
}

# Monitoring information
output "monitoring_dashboard" {
  description = "Cloud Monitoring dashboard information"
  value = {
    id   = google_monitoring_dashboard.pipeline_dashboard.id
    name = "Multi-Stream Data Processing Pipeline"
    url  = "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.pipeline_dashboard.id)[3]}?project=${var.project_id}"
  }
}

output "monitoring_alert_policy" {
  description = "Cloud Monitoring alert policy information"
  value = {
    id           = google_monitoring_alert_policy.high_message_backlog.id
    display_name = google_monitoring_alert_policy.high_message_backlog.display_name
    enabled      = google_monitoring_alert_policy.high_message_backlog.enabled
  }
}

# Connection strings and endpoints
output "connection_info" {
  description = "Connection information for external applications"
  value = {
    pubsub_lite_endpoints = {
      for key, topic in google_pubsub_lite_topic.topics : key => {
        topic_path = "projects/${var.project_id}/locations/${var.region}/topics/${topic.name}"
        analytics_subscription_path = "projects/${var.project_id}/locations/${var.region}/subscriptions/${google_pubsub_lite_subscription.analytics_subscriptions[key].name}"
        workflow_subscription_path = key != "system_logs" ? "projects/${var.project_id}/locations/${var.region}/subscriptions/${google_pubsub_lite_subscription.workflow_subscriptions[key].name}" : null
      }
    }
    bigquery_connection_string = "${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}"
    storage_bucket_url = "gs://${google_storage_bucket.data_lake.name}"
  }
}

# Dataflow pipeline information
output "dataflow_staging_locations" {
  description = "Cloud Storage locations for Dataflow staging and temporary files"
  value = {
    staging_location = "gs://${google_storage_bucket.data_lake.name}/dataflow-staging"
    temp_location    = "gs://${google_storage_bucket.data_lake.name}/dataflow-temp"
    template_location = "gs://${google_storage_bucket.data_lake.name}/templates"
  }
}

# Cost optimization information
output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    pubsub_lite_reserved_capacity = google_pubsub_lite_reservation.reservation.throughput_capacity
    bigquery_partition_expiration = "${var.retention_days} days"
    storage_lifecycle_transitions = [
      "Standard → Nearline at 30 days",
      "Nearline → Coldline at 90 days",
      "Delete after ${var.retention_days} days"
    ]
    clustering_enabled = true
    time_partitioning_enabled = true
  }
}

# Security information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account_email = google_service_account.app_integration_sa.email
    iam_roles_granted = [
      "roles/pubsublite.editor",
      "roles/bigquery.dataEditor",
      "roles/storage.objectAdmin",
      "roles/dataflow.admin",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter"
    ]
    bucket_versioning_enabled = google_storage_bucket.data_lake.versioning[0].enabled
    uniform_bucket_level_access = null  # Would be set if enabled
  }
}

# Deployment summary
output "deployment_summary" {
  description = "High-level summary of deployed resources"
  value = {
    pubsub_lite_topics = length(google_pubsub_lite_topic.topics)
    pubsub_lite_subscriptions = length(google_pubsub_lite_subscription.analytics_subscriptions) + length(google_pubsub_lite_subscription.workflow_subscriptions)
    bigquery_tables = length([
      google_bigquery_table.iot_sensor_data,
      google_bigquery_table.application_events,
      google_bigquery_table.system_logs_summary
    ])
    storage_buckets = 1
    service_accounts = 1
    monitoring_dashboards = 1
    alert_policies = 1
    enabled_apis = length(google_project_service.apis)
  }
}

# Health check endpoints
output "health_check_queries" {
  description = "Sample queries for health checking the deployment"
  value = {
    pubsub_lite_topic_status = "gcloud pubsub lite-topics list --location=${var.region} --project=${var.project_id}"
    bigquery_table_status = "bq ls -p ${var.project_id} ${google_bigquery_dataset.analytics_dataset.dataset_id}"
    storage_bucket_status = "gsutil ls gs://${google_storage_bucket.data_lake.name}"
    service_account_status = "gcloud iam service-accounts describe ${google_service_account.app_integration_sa.email} --project=${var.project_id}"
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test Pub/Sub Lite topic publishing using the sample Python script",
    "2. Deploy Cloud Dataflow pipeline using the provided template",
    "3. Configure Application Integration workflows for your business logic",
    "4. Set up monitoring alerts and notification channels",
    "5. Test end-to-end data flow from publishing to BigQuery",
    "6. Optimize partition counts and throughput based on actual usage",
    "7. Implement security best practices and access controls",
    "8. Set up automated backup and disaster recovery procedures"
  ]
}