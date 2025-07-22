# Output values for browser-based AI applications infrastructure
# These outputs provide essential information for deployment verification and integration

# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Cloud Run service outputs
output "cloud_run_service_name" {
  description = "Name of the deployed Cloud Run service"
  value       = var.enable_apis ? google_cloud_run_v2_service.ai_chat_service[0].name : null
}

output "cloud_run_service_url" {
  description = "URL of the deployed AI chat assistant service"
  value       = var.enable_apis ? google_cloud_run_v2_service.ai_chat_service[0].uri : null
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = var.enable_apis ? google_cloud_run_v2_service.ai_chat_service[0].location : null
}

output "cloud_run_service_account_email" {
  description = "Email of the service account used by Cloud Run"
  value       = var.enable_apis ? google_service_account.cloud_run_sa[0].email : null
}

# Artifact Registry outputs
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = var.enable_apis ? google_artifact_registry_repository.ai_app_repo[0].repository_id : null
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository for pushing images"
  value       = var.enable_apis ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}" : null
}

output "container_image_url" {
  description = "Base URL for container images in the repository"
  value       = var.enable_apis ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}" : null
}

# Cloud Build outputs
output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger for automated deployment"
  value       = var.enable_apis ? google_cloudbuild_trigger.ai_app_trigger[0].name : null
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = var.enable_apis ? google_cloudbuild_trigger.ai_app_trigger[0].trigger_id : null
}

# Vertex AI configuration outputs
output "vertex_ai_location" {
  description = "Location configured for Vertex AI resources"
  value       = var.vertex_ai_location
}

output "vertex_ai_project_id" {
  description = "Project ID for Vertex AI API calls"
  value       = var.project_id
}

# Secret Manager outputs
output "app_config_secret_name" {
  description = "Name of the Secret Manager secret containing application configuration"
  value       = var.enable_apis ? google_secret_manager_secret.app_config[0].secret_id : null
}

output "app_config_secret_version" {
  description = "Version of the application configuration secret"
  value       = var.enable_apis ? google_secret_manager_secret_version.app_config_version[0].version : null
}

# Service account outputs
output "service_accounts" {
  description = "Service accounts created for the AI application"
  value = var.enable_apis ? {
    cloud_run = {
      email        = google_service_account.cloud_run_sa[0].email
      display_name = google_service_account.cloud_run_sa[0].display_name
      unique_id    = google_service_account.cloud_run_sa[0].unique_id
    }
  } : {}
}

# API services outputs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the project"
  value       = var.enable_apis ? local.required_apis : []
}

# Deployment commands and instructions
output "deployment_instructions" {
  description = "Instructions for deploying the AI application"
  value = var.enable_apis ? {
    cloud_shell_command = "Open https://ide.cloud.google.com and clone your application repository"
    docker_build        = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}:latest ."
    docker_push         = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}:latest"
    manual_deploy       = "gcloud run deploy ${var.service_name} --image=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}:latest --region=${var.region}"
  } : {}
}

# Testing and validation outputs
output "test_endpoints" {
  description = "Endpoints for testing the deployed AI application"
  value = var.enable_apis ? {
    health_check = "${google_cloud_run_v2_service.ai_chat_service[0].uri}/health"
    chat_api     = "${google_cloud_run_v2_service.ai_chat_service[0].uri}/api/chat"
    web_ui       = google_cloud_run_v2_service.ai_chat_service[0].uri
  } : {}
}

# Resource URLs for management
output "management_urls" {
  description = "URLs for managing deployed resources in Google Cloud Console"
  value = var.enable_apis ? {
    cloud_run_service    = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.ai_chat_service[0].name}/metrics"
    artifact_registry    = "https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}"
    cloud_build_history  = "https://console.cloud.google.com/cloud-build/builds"
    vertex_ai_console    = "https://console.cloud.google.com/vertex-ai"
    cloud_shell_editor   = "https://ide.cloud.google.com"
  } : {}
}

# Cost and resource information
output "resource_summary" {
  description = "Summary of created resources and their estimated costs"
  value = var.enable_apis ? {
    cloud_run = {
      cpu_allocation    = var.cloud_run_cpu
      memory_allocation = var.cloud_run_memory
      min_instances     = var.cloud_run_min_instances
      max_instances     = var.cloud_run_max_instances
      pricing_model     = "Pay-per-use with minimum instance pricing"
    }
    vertex_ai = {
      location      = var.vertex_ai_location
      models_used   = ["gemini-1.5-flash", "gemini-1.5-pro"]
      pricing_model = "Pay-per-request"
    }
    artifact_registry = {
      storage_cost = "Pay-per-GB stored"
      cleanup_policy = "Automatic cleanup after 30 days"
    }
    cloud_build = {
      pricing_model = "Pay-per-build minute"
      timeout       = "${var.cloud_build_timeout} seconds"
    }
  } : {}
}

# Environment configuration
output "environment_variables" {
  description = "Environment variables configured for the application"
  value = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    GOOGLE_CLOUD_REGION  = var.vertex_ai_location
    ENVIRONMENT          = var.environment
  }
}

# Security and compliance information
output "security_configuration" {
  description = "Security settings and compliance information"
  value = var.enable_apis ? {
    iam_roles_granted = [
      "roles/aiplatform.user",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter",
      "roles/secretmanager.secretAccessor"
    ]
    service_account_principle = "Least privilege access"
    public_access_enabled     = var.allow_unauthenticated
    secret_management        = "Google Secret Manager"
  } : {}
}