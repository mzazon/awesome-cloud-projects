# Project and resource identification outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Bigtable outputs
output "bigtable_instance_id" {
  description = "The ID of the Bigtable instance for feature storage"
  value       = google_bigtable_instance.feature_store.name
}

output "bigtable_instance_name" {
  description = "The full name of the Bigtable instance"
  value       = google_bigtable_instance.feature_store.id
}

output "bigtable_cluster_id" {
  description = "The ID of the Bigtable cluster"
  value       = google_bigtable_instance.feature_store.cluster[0].cluster_id
}

output "bigtable_cluster_zone" {
  description = "The zone of the Bigtable cluster"
  value       = google_bigtable_instance.feature_store.cluster[0].zone
}

output "bigtable_cluster_num_nodes" {
  description = "The number of nodes in the Bigtable cluster"
  value       = google_bigtable_instance.feature_store.cluster[0].num_nodes
}

output "bigtable_cluster_storage_type" {
  description = "The storage type of the Bigtable cluster"
  value       = google_bigtable_instance.feature_store.cluster[0].storage_type
}

output "bigtable_table_names" {
  description = "List of Bigtable table names created for feature storage"
  value       = [for table in google_bigtable_table.feature_tables : table.name]
}

# Redis cache outputs
output "redis_instance_id" {
  description = "The ID of the Redis instance for feature caching"
  value       = google_redis_instance.feature_cache.name
}

output "redis_instance_host" {
  description = "The host/IP address of the Redis instance"
  value       = google_redis_instance.feature_cache.host
  sensitive   = true
}

output "redis_instance_port" {
  description = "The port number of the Redis instance"
  value       = google_redis_instance.feature_cache.port
}

output "redis_instance_memory_size" {
  description = "The memory size of the Redis instance in GB"
  value       = google_redis_instance.feature_cache.memory_size_gb
}

output "redis_instance_tier" {
  description = "The service tier of the Redis instance"
  value       = google_redis_instance.feature_cache.tier
}

output "redis_auth_string" {
  description = "The AUTH string for the Redis instance"
  value       = google_redis_instance.feature_cache.auth_string
  sensitive   = true
}

# Vertex AI outputs
output "vertex_ai_model_id" {
  description = "The ID of the Vertex AI model"
  value       = google_vertex_ai_model.inference_model.id
}

output "vertex_ai_model_name" {
  description = "The name of the Vertex AI model"
  value       = google_vertex_ai_model.inference_model.name
}

output "vertex_ai_endpoint_id" {
  description = "The ID of the Vertex AI endpoint"
  value       = google_vertex_ai_endpoint.inference_endpoint.id
}

output "vertex_ai_endpoint_name" {
  description = "The name of the Vertex AI endpoint"
  value       = google_vertex_ai_endpoint.inference_endpoint.name
}

output "vertex_ai_endpoint_display_name" {
  description = "The display name of the Vertex AI endpoint"
  value       = google_vertex_ai_endpoint.inference_endpoint.display_name
}

output "vertex_ai_deployed_model_id" {
  description = "The ID of the deployed model on the Vertex AI endpoint"
  value       = google_vertex_ai_endpoint_deployed_model.inference_deployment.id
}

output "vertex_ai_endpoint_url" {
  description = "The URL for making predictions to the Vertex AI endpoint"
  value       = "https://${var.region}-aiplatform.googleapis.com/v1/${google_vertex_ai_endpoint.inference_endpoint.name}:predict"
}

# Cloud Functions outputs
output "cloud_function_name" {
  description = "The name of the Cloud Function for inference orchestration"
  value       = google_cloudfunctions2_function.inference_pipeline.name
}

output "cloud_function_url" {
  description = "The URL of the Cloud Function for inference requests"
  value       = google_cloudfunctions2_function.inference_pipeline.service_config[0].uri
}

output "cloud_function_location" {
  description = "The location of the Cloud Function"
  value       = google_cloudfunctions2_function.inference_pipeline.location
}

output "cloud_function_service_account" {
  description = "The service account used by the Cloud Function"
  value       = google_cloudfunctions2_function.inference_pipeline.service_config[0].service_account_email
}

# Storage outputs
output "model_artifacts_bucket_name" {
  description = "The name of the Cloud Storage bucket for model artifacts"
  value       = var.enable_storage_bucket ? google_storage_bucket.model_artifacts[0].name : null
}

output "model_artifacts_bucket_url" {
  description = "The URL of the Cloud Storage bucket for model artifacts"
  value       = var.enable_storage_bucket ? google_storage_bucket.model_artifacts[0].url : null
}

output "function_source_bucket_name" {
  description = "The name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Service account outputs
output "bigtable_service_account_email" {
  description = "The email address of the Bigtable service account"
  value       = var.enable_custom_service_accounts ? google_service_account.bigtable_sa[0].email : null
}

output "vertex_ai_service_account_email" {
  description = "The email address of the Vertex AI service account"
  value       = var.enable_custom_service_accounts ? google_service_account.vertex_ai_sa[0].email : null
}

output "cloud_function_service_account_email" {
  description = "The email address of the Cloud Function service account"
  value       = var.enable_custom_service_accounts ? google_service_account.cloud_function_sa[0].email : null
}

# Monitoring outputs
output "monitoring_alert_policy_latency_id" {
  description = "The ID of the latency monitoring alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.inference_latency_alert[0].name : null
}

output "monitoring_alert_policy_error_rate_id" {
  description = "The ID of the error rate monitoring alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.inference_error_rate_alert[0].name : null
}

output "monitoring_dashboard_url" {
  description = "The URL of the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.inference_pipeline_dashboard[0].id}?project=${var.project_id}" : null
}

output "log_based_metrics" {
  description = "List of log-based metrics created for monitoring"
  value = var.enable_monitoring ? [
    google_logging_metric.inference_latency_metric[0].name,
    google_logging_metric.cache_hit_ratio_metric[0].name
  ] : []
}

# Connection and configuration outputs
output "inference_pipeline_connection_info" {
  description = "Connection information for the inference pipeline"
  value = {
    cloud_function_url    = google_cloudfunctions2_function.inference_pipeline.service_config[0].uri
    vertex_ai_endpoint_id = google_vertex_ai_endpoint.inference_endpoint.id
    bigtable_instance_id  = google_bigtable_instance.feature_store.name
    redis_host           = google_redis_instance.feature_cache.host
    redis_port           = google_redis_instance.feature_cache.port
  }
  sensitive = true
}

# Environment variables for client applications
output "client_environment_variables" {
  description = "Environment variables for client applications"
  value = {
    INFERENCE_FUNCTION_URL = google_cloudfunctions2_function.inference_pipeline.service_config[0].uri
    PROJECT_ID            = var.project_id
    REGION                = var.region
    BIGTABLE_INSTANCE_ID  = google_bigtable_instance.feature_store.name
    REDIS_HOST            = google_redis_instance.feature_cache.host
    REDIS_PORT            = google_redis_instance.feature_cache.port
    VERTEX_AI_ENDPOINT_ID = google_vertex_ai_endpoint.inference_endpoint.id
  }
  sensitive = true
}

# Performance and capacity information
output "infrastructure_capacity" {
  description = "Capacity and performance information for the infrastructure"
  value = {
    bigtable_cluster_nodes       = google_bigtable_instance.feature_store.cluster[0].num_nodes
    bigtable_estimated_reads_per_second = google_bigtable_instance.feature_store.cluster[0].num_nodes * 17000
    bigtable_estimated_writes_per_second = google_bigtable_instance.feature_store.cluster[0].num_nodes * 14000
    redis_memory_gb             = google_redis_instance.feature_cache.memory_size_gb
    cloud_function_max_instances = var.cloud_function_max_instances
    cloud_function_min_instances = var.cloud_function_min_instances
    vertex_ai_min_replicas      = var.vertex_ai_min_replica_count
    vertex_ai_max_replicas      = var.vertex_ai_max_replica_count
  }
}

# Cost estimation information
output "cost_estimation_info" {
  description = "Information for cost estimation and monitoring"
  value = {
    bigtable_cluster_nodes = google_bigtable_instance.feature_store.cluster[0].num_nodes
    bigtable_storage_type  = google_bigtable_instance.feature_store.cluster[0].storage_type
    redis_memory_gb        = google_redis_instance.feature_cache.memory_size_gb
    redis_tier            = google_redis_instance.feature_cache.tier
    vertex_ai_machine_type = var.vertex_ai_machine_type
    vertex_ai_accelerator_type = var.vertex_ai_accelerator_type
    vertex_ai_accelerator_count = var.vertex_ai_accelerator_count
    cloud_function_memory = var.cloud_function_memory
    region                = var.region
  }
}

# Deployment validation outputs
output "deployment_validation" {
  description = "Information for validating the deployment"
  value = {
    all_apis_enabled = [
      "bigtable.googleapis.com",
      "aiplatform.googleapis.com",
      "cloudfunctions.googleapis.com",
      "monitoring.googleapis.com",
      "redis.googleapis.com",
      "storage.googleapis.com",
      "cloudbuild.googleapis.com",
      "run.googleapis.com",
      "eventarc.googleapis.com"
    ]
    bigtable_tables_created = length(google_bigtable_table.feature_tables)
    monitoring_enabled     = var.enable_monitoring
    custom_service_accounts = var.enable_custom_service_accounts
    deletion_protection    = var.enable_deletion_protection
  }
}

# Sample curl command for testing
output "sample_inference_request" {
  description = "Sample curl command for testing the inference pipeline"
  value = <<-EOT
curl -X POST "${google_cloudfunctions2_function.inference_pipeline.service_config[0].uri}" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user_12345",
    "item_id": "item_67890",
    "context": {
      "timestamp": "2025-07-12T10:00:00Z",
      "device": "mobile"
    }
  }'
EOT
}

# Terraform state information
output "terraform_state_info" {
  description = "Information about the Terraform state and resources"
  value = {
    resource_count = length([
      google_bigtable_instance.feature_store.name,
      google_redis_instance.feature_cache.name,
      google_vertex_ai_model.inference_model.name,
      google_vertex_ai_endpoint.inference_endpoint.name,
      google_cloudfunctions2_function.inference_pipeline.name
    ])
    resource_prefix = var.resource_prefix
    random_suffix   = random_id.suffix.hex
    labels_applied  = var.labels
  }
}