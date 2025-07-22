# ==============================================================================
# Real-Time Event Processing Outputs
# ==============================================================================
# Output values for the real-time event processing infrastructure
# These outputs provide important connection details and resource information
# ==============================================================================

# ==============================================================================
# Project and Location Information
# ==============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = var.prefix
}

# ==============================================================================
# Networking Outputs
# ==============================================================================

output "vpc_network_id" {
  description = "The ID of the VPC network created for event processing"
  value       = google_compute_network.event_processing_vpc.id
}

output "vpc_network_name" {
  description = "The name of the VPC network created for event processing"
  value       = google_compute_network.event_processing_vpc.name
}

output "main_subnet_id" {
  description = "The ID of the main subnet for application resources"
  value       = google_compute_subnetwork.main_subnet.id
}

output "main_subnet_cidr" {
  description = "The CIDR block of the main subnet"
  value       = google_compute_subnetwork.main_subnet.ip_cidr_range
}

output "vpc_connector_id" {
  description = "The ID of the VPC Access Connector for Cloud Functions"
  value       = google_vpc_access_connector.function_connector.id
}

# ==============================================================================
# Cloud Memorystore Redis Outputs
# ==============================================================================

output "redis_instance_id" {
  description = "The instance ID of the Cloud Memorystore Redis instance"
  value       = google_memorystore_instance.redis_cache.instance_id
}

output "redis_instance_name" {
  description = "The full resource name of the Redis instance"
  value       = google_memorystore_instance.redis_cache.name
}

output "redis_host" {
  description = "The private IP address of the Redis instance"
  value       = google_memorystore_instance.redis_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address
  sensitive   = true
}

output "redis_port" {
  description = "The port number for connecting to the Redis instance"
  value       = 6379
}

output "redis_connection_string" {
  description = "The complete connection string for the Redis instance"
  value       = "${google_memorystore_instance.redis_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address}:6379"
  sensitive   = true
}

output "redis_engine_version" {
  description = "The engine version of the Redis instance"
  value       = google_memorystore_instance.redis_cache.engine_version
}

output "redis_node_type" {
  description = "The node type of the Redis instance"
  value       = var.redis_node_type
}

output "redis_shard_count" {
  description = "The number of shards in the Redis instance"
  value       = var.redis_shard_count
}

output "redis_replica_count" {
  description = "The number of replicas per shard in the Redis instance"
  value       = var.redis_replica_count
}

# ==============================================================================
# Pub/Sub Outputs
# ==============================================================================

output "pubsub_topic_id" {
  description = "The ID of the main Pub/Sub topic for event ingestion"
  value       = google_pubsub_topic.events_topic.id
}

output "pubsub_topic_name" {
  description = "The name of the main Pub/Sub topic"
  value       = google_pubsub_topic.events_topic.name
}

output "pubsub_subscription_id" {
  description = "The ID of the Pub/Sub subscription for Cloud Functions"
  value       = google_pubsub_subscription.events_subscription.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.events_subscription.name
}

output "dead_letter_topic_id" {
  description = "The ID of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter_topic.id
}

output "dead_letter_topic_name" {
  description = "The name of the dead letter topic"
  value       = google_pubsub_topic.dead_letter_topic.name
}

# ==============================================================================
# BigQuery Outputs
# ==============================================================================

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for event analytics"
  value       = google_bigquery_dataset.event_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.event_analytics.location
}

output "bigquery_table_id" {
  description = "The ID of the BigQuery table for processed events"
  value       = google_bigquery_table.processed_events.table_id
}

output "bigquery_table_full_name" {
  description = "The full name of the BigQuery table (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.event_analytics.dataset_id}.${google_bigquery_table.processed_events.table_id}"
}

# ==============================================================================
# Cloud Functions Outputs
# ==============================================================================

output "function_name" {
  description = "The name of the Cloud Function for event processing"
  value       = google_cloudfunctions2_function.event_processor.name
}

output "function_id" {
  description = "The ID of the Cloud Function"
  value       = google_cloudfunctions2_function.event_processor.id
}

output "function_service_account_email" {
  description = "The email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_memory" {
  description = "The memory allocation for the Cloud Function"
  value       = var.function_memory
}

output "function_timeout" {
  description = "The timeout setting for the Cloud Function"
  value       = var.function_timeout_seconds
}

# ==============================================================================
# Storage Outputs
# ==============================================================================

output "function_source_bucket_name" {
  description = "The name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "The URL of the function source bucket"
  value       = google_storage_bucket.function_source.url
}

# ==============================================================================
# Security Outputs
# ==============================================================================

output "service_accounts" {
  description = "Map of service accounts created for the event processing system"
  value = {
    function = {
      email        = google_service_account.function_sa.email
      display_name = google_service_account.function_sa.display_name
      account_id   = google_service_account.function_sa.account_id
    }
  }
}

# ==============================================================================
# Monitoring Outputs
# ==============================================================================

output "monitoring_alert_policy_names" {
  description = "Names of the monitoring alert policies created"
  value = var.monitoring_enabled ? [
    google_monitoring_alert_policy.high_error_rate[0].display_name
  ] : []
}

output "log_metric_names" {
  description = "Names of the log-based metrics created for monitoring"
  value = [
    google_logging_metric.event_processing_rate.name
  ]
}

# ==============================================================================
# Connection and Testing Information
# ==============================================================================

output "testing_commands" {
  description = "Useful commands for testing the event processing pipeline"
  value = {
    publish_test_event = "gcloud pubsub topics publish ${google_pubsub_topic.events_topic.name} --message='{\"id\":\"test-001\",\"userId\":\"user123\",\"type\":\"login\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"metadata\":{\"source\":\"web\"}}'"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.event_processor.name} --region=${var.region} --limit=50"
    query_bigquery     = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as event_count FROM \\`${var.project_id}.${google_bigquery_dataset.event_analytics.dataset_id}.${google_bigquery_table.processed_events.table_id}\\` WHERE DATE(timestamp) = CURRENT_DATE()'"
  }
}

output "console_urls" {
  description = "Google Cloud Console URLs for monitoring and management"
  value = {
    redis_instance    = "https://console.cloud.google.com/memorystore/redis/instances/${google_memorystore_instance.redis_cache.instance_id}/details?project=${var.project_id}&region=${var.region}"
    pubsub_topic      = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.events_topic.name}?project=${var.project_id}"
    bigquery_dataset  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.event_analytics.dataset_id}"
    cloud_function    = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.event_processor.name}?project=${var.project_id}"
    monitoring        = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# ==============================================================================
# Cost Optimization Information
# ==============================================================================

output "cost_optimization_tips" {
  description = "Tips for optimizing costs in the event processing system"
  value = {
    redis_scaling = "Consider using SHARED_CORE_NANO for development/testing and scale up for production workloads"
    function_scaling = "Use min_instances=0 for cost optimization in low-traffic scenarios"
    bigquery_partitioning = "Partition expiration is set to ${var.bigquery_partition_expiration_ms / 86400000} days to manage storage costs"
    pubsub_retention = "Message retention is configured for optimal balance between reliability and cost"
  }
}

# ==============================================================================
# Summary Information
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed event processing infrastructure"
  value = {
    infrastructure_type = "Real-time Event Processing with Cloud Memorystore and Pub/Sub"
    primary_services = [
      "Cloud Memorystore for Redis",
      "Cloud Pub/Sub", 
      "Cloud Functions",
      "BigQuery",
      "Cloud Monitoring"
    ]
    estimated_monthly_cost = "Varies based on usage. Check Google Cloud Calculator for detailed estimates."
    key_features = [
      "Sub-millisecond Redis caching",
      "Serverless event processing", 
      "Automatic scaling",
      "Dead letter queue handling",
      "Real-time analytics",
      "Comprehensive monitoring"
    ]
  }
}