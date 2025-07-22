# Outputs for Personalized Recommendation APIs with Vertex AI and Cloud Run
# This file defines all outputs that provide important information about the deployed infrastructure

# Project and location information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for zonal resources"
  value       = var.zone
}

output "environment" {
  description = "The environment name (dev, staging, prod)"
  value       = var.environment
}

# Cloud Run API service outputs
output "api_service_name" {
  description = "The name of the Cloud Run service hosting the recommendation API"
  value       = google_cloud_run_service.ml_api.name
}

output "api_service_url" {
  description = "The URL of the deployed Cloud Run recommendation API service"
  value       = google_cloud_run_service.ml_api.status[0].url
}

output "api_service_location" {
  description = "The location where the Cloud Run service is deployed"
  value       = google_cloud_run_service.ml_api.location
}

output "api_service_revision" {
  description = "The latest revision of the Cloud Run service"
  value       = google_cloud_run_service.ml_api.status[0].latest_ready_revision_name
}

# Storage outputs
output "training_data_bucket_name" {
  description = "The name of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.name
}

output "training_data_bucket_url" {
  description = "The URL of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.url
}

output "model_artifacts_bucket_name" {
  description = "The name of the Cloud Storage bucket for model artifacts"
  value       = google_storage_bucket.model_artifacts.name
}

output "model_artifacts_bucket_url" {
  description = "The URL of the Cloud Storage bucket for model artifacts"
  value       = google_storage_bucket.model_artifacts.url
}

# BigQuery outputs
output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for user interactions"
  value       = google_bigquery_dataset.user_interactions.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.user_interactions.location
}

output "bigquery_table_id" {
  description = "The ID of the BigQuery table for user interactions"
  value       = google_bigquery_table.interactions.table_id
}

output "bigquery_table_reference" {
  description = "Full reference to the BigQuery table (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.user_interactions.dataset_id}.${google_bigquery_table.interactions.table_id}"
}

# Vertex AI outputs
output "vertex_ai_dataset_id" {
  description = "The ID of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.ml_dataset.name
}

output "vertex_ai_dataset_display_name" {
  description = "The display name of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.ml_dataset.display_name
}

output "vertex_ai_model_id" {
  description = "The ID of the Vertex AI model"
  value       = google_vertex_ai_model.recommendation_model.name
}

output "vertex_ai_model_display_name" {
  description = "The display name of the Vertex AI model"
  value       = google_vertex_ai_model.recommendation_model.display_name
}

output "vertex_ai_endpoint_id" {
  description = "The ID of the Vertex AI endpoint"
  value       = google_vertex_ai_endpoint.ml_endpoint.name
}

output "vertex_ai_endpoint_display_name" {
  description = "The display name of the Vertex AI endpoint"
  value       = google_vertex_ai_endpoint.ml_endpoint.display_name
}

# Service account outputs
output "ml_api_service_account_email" {
  description = "The email address of the ML API service account"
  value       = google_service_account.ml_api_sa.email
}

output "ml_api_service_account_id" {
  description = "The ID of the ML API service account"
  value       = google_service_account.ml_api_sa.id
}

output "ml_vertex_service_account_email" {
  description = "The email address of the Vertex AI service account"
  value       = google_service_account.ml_vertex_sa.email
}

output "ml_vertex_service_account_id" {
  description = "The ID of the Vertex AI service account"
  value       = google_service_account.ml_vertex_sa.id
}

output "cloudbuild_service_account_email" {
  description = "The email address of the Cloud Build service account"
  value       = google_service_account.cloudbuild_sa.email
}

output "cloudbuild_service_account_id" {
  description = "The ID of the Cloud Build service account"
  value       = google_service_account.cloudbuild_sa.id
}

# Cloud Build outputs
output "cloudbuild_trigger_id" {
  description = "The ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.ml_api_build.id
}

output "cloudbuild_trigger_name" {
  description = "The name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.ml_api_build.name
}

# API endpoints for testing and integration
output "api_endpoints" {
  description = "Map of API endpoints for testing and integration"
  value = {
    health_check   = "${google_cloud_run_service.ml_api.status[0].url}/"
    recommendations = "${google_cloud_run_service.ml_api.status[0].url}/recommend"
    feedback       = "${google_cloud_run_service.ml_api.status[0].url}/feedback"
  }
}

# Configuration summary
output "deployment_config" {
  description = "Summary of deployment configuration"
  value = {
    project_id   = var.project_id
    region       = var.region
    environment  = var.environment
    api_config = {
      min_instances = var.api_config.min_instances
      max_instances = var.api_config.max_instances
      cpu_limit     = var.api_config.cpu_limit
      memory_limit  = var.api_config.memory_limit
    }
    ml_config = {
      embedding_dimension = var.ml_model_config.embedding_dimension
      training_machine_type = var.ml_model_config.training_machine_type
      serving_machine_type = var.ml_model_config.serving_machine_type
    }
    storage_config = {
      enable_versioning = var.storage_config.enable_versioning
      uniform_bucket_level_access = var.storage_config.uniform_bucket_level_access
    }
    feature_flags = var.feature_flags
  }
}

# Security and compliance outputs
output "security_config" {
  description = "Security configuration details"
  value = {
    kms_key_name = var.kms_key_name
    vpc_network_name = var.vpc_network_name
    uniform_bucket_level_access = var.storage_config.uniform_bucket_level_access
    workload_identity_enabled = var.feature_flags.enable_workload_identity
    private_endpoints_enabled = var.feature_flags.enable_private_endpoints
  }
  sensitive = true
}

# Resource naming information
output "resource_naming" {
  description = "Resource naming convention used for this deployment"
  value = {
    prefix = "${var.environment}-ml-rec"
    suffix = random_id.suffix.hex
    training_data_bucket = local.training_data_bucket
    model_artifacts_bucket = local.model_artifacts_bucket
    api_service_name = local.api_service_name
    dataset_id = local.dataset_id
  }
}

# Cost estimation outputs
output "cost_estimation_info" {
  description = "Information for cost estimation and optimization"
  value = {
    region = var.region
    api_scaling = {
      min_instances = var.api_config.min_instances
      max_instances = var.api_config.max_instances
      cpu_limit     = var.api_config.cpu_limit
      memory_limit  = var.api_config.memory_limit
    }
    ml_resources = {
      training_machine_type = var.ml_model_config.training_machine_type
      serving_machine_type  = var.ml_model_config.serving_machine_type
      serving_min_replicas  = var.ml_model_config.serving_min_replicas
      serving_max_replicas  = var.ml_model_config.serving_max_replicas
    }
    storage_lifecycle = {
      standard_days = var.storage_config.standard_storage_days
      nearline_days = var.storage_config.nearline_storage_days
      coldline_days = var.storage_config.coldline_storage_days
    }
    bigquery_retention = var.bigquery_config.default_table_expiration_days
    cost_optimization = var.cost_optimization
  }
}

# Monitoring and observability outputs
output "monitoring_config" {
  description = "Monitoring and observability configuration"
  value = {
    enable_monitoring = var.monitoring_config.enable_monitoring
    enable_alerting = var.monitoring_config.enable_alerting
    log_retention_days = var.monitoring_config.log_retention_days
    enable_performance_monitoring = var.monitoring_config.enable_performance_monitoring
    enable_cost_monitoring = var.monitoring_config.enable_cost_monitoring
    budget_amount = var.monitoring_config.monthly_budget_amount
    budget_currency = var.monitoring_config.budget_currency
  }
}

# Development and testing outputs
output "development_info" {
  description = "Information useful for development and testing"
  value = {
    # API testing commands
    curl_health_check = "curl -X GET ${google_cloud_run_service.ml_api.status[0].url}/"
    curl_recommend = "curl -X POST ${google_cloud_run_service.ml_api.status[0].url}/recommend -H 'Content-Type: application/json' -d '{\"user_id\": \"user_123\", \"num_recommendations\": 5}'"
    curl_feedback = "curl -X POST ${google_cloud_run_service.ml_api.status[0].url}/feedback -H 'Content-Type: application/json' -d '{\"user_id\": \"user_123\", \"item_id\": \"item_456\", \"feedback_type\": \"like\"}'"
    
    # Storage access commands
    gsutil_training_data = "gsutil ls gs://${google_storage_bucket.training_data.name}/"
    gsutil_model_artifacts = "gsutil ls gs://${google_storage_bucket.model_artifacts.name}/"
    
    # BigQuery access
    bq_dataset = "bq ls ${google_bigquery_dataset.user_interactions.dataset_id}"
    bq_table_schema = "bq show ${var.project_id}:${google_bigquery_dataset.user_interactions.dataset_id}.${google_bigquery_table.interactions.table_id}"
    
    # Vertex AI commands
    vertex_ai_dataset = "gcloud ai datasets describe ${google_vertex_ai_dataset.ml_dataset.name} --region=${var.region}"
    vertex_ai_endpoint = "gcloud ai endpoints describe ${google_vertex_ai_endpoint.ml_endpoint.name} --region=${var.region}"
  }
}

# Infrastructure validation outputs
output "validation_checks" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    # Service health checks
    api_health = "curl -f ${google_cloud_run_service.ml_api.status[0].url}/ || echo 'API health check failed'"
    
    # Resource existence checks
    storage_buckets = "gsutil ls -p ${var.project_id} | grep -E '(training-data|models)' || echo 'Storage buckets not found'"
    bigquery_dataset = "bq ls -p ${var.project_id} | grep ${google_bigquery_dataset.user_interactions.dataset_id} || echo 'BigQuery dataset not found'"
    
    # Service account checks
    service_accounts = "gcloud iam service-accounts list --filter='email~ml-rec' --format='value(email)'"
    
    # Vertex AI resources
    vertex_resources = "gcloud ai endpoints list --region=${var.region} --filter='displayName~ml-rec'"
    
    # IAM permissions
    api_permissions = "gcloud projects get-iam-policy ${var.project_id} --flatten='bindings[].members' --filter='bindings.members:serviceAccount:${google_service_account.ml_api_sa.email}' --format='value(bindings.role)'"
  }
}

# Cleanup information
output "cleanup_info" {
  description = "Information for cleaning up resources"
  value = {
    # Resource identifiers for cleanup
    project_id = var.project_id
    region = var.region
    
    # Storage buckets to clean up
    storage_buckets = [
      google_storage_bucket.training_data.name,
      google_storage_bucket.model_artifacts.name
    ]
    
    # BigQuery datasets to clean up
    bigquery_datasets = [
      google_bigquery_dataset.user_interactions.dataset_id
    ]
    
    # Service accounts to clean up
    service_accounts = [
      google_service_account.ml_api_sa.email,
      google_service_account.ml_vertex_sa.email,
      google_service_account.cloudbuild_sa.email
    ]
    
    # Vertex AI resources to clean up
    vertex_ai_resources = {
      dataset_id = google_vertex_ai_dataset.ml_dataset.name
      model_id = google_vertex_ai_model.recommendation_model.name
      endpoint_id = google_vertex_ai_endpoint.ml_endpoint.name
    }
    
    # Cloud Run services to clean up
    cloud_run_services = [
      google_cloud_run_service.ml_api.name
    ]
    
    # Cloud Build triggers to clean up
    cloud_build_triggers = [
      google_cloudbuild_trigger.ml_api_build.id
    ]
  }
}

# Integration information
output "integration_info" {
  description = "Information for integrating with external systems"
  value = {
    # API integration
    api_base_url = google_cloud_run_service.ml_api.status[0].url
    api_service_account = google_service_account.ml_api_sa.email
    
    # Data integration
    bigquery_table_reference = "${var.project_id}.${google_bigquery_dataset.user_interactions.dataset_id}.${google_bigquery_table.interactions.table_id}"
    training_data_bucket = google_storage_bucket.training_data.name
    model_artifacts_bucket = google_storage_bucket.model_artifacts.name
    
    # ML pipeline integration
    vertex_ai_dataset = google_vertex_ai_dataset.ml_dataset.name
    vertex_ai_endpoint = google_vertex_ai_endpoint.ml_endpoint.name
    ml_service_account = google_service_account.ml_vertex_sa.email
    
    # CI/CD integration
    cloudbuild_trigger = google_cloudbuild_trigger.ml_api_build.id
    container_registry = "gcr.io/${var.project_id}"
    
    # Monitoring integration
    project_id = var.project_id
    region = var.region
    environment = var.environment
  }
}