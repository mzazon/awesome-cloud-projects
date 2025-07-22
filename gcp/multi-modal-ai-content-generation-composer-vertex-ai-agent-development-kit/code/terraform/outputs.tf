# Outputs for Multi-Modal AI Content Generation Pipeline
# These outputs provide essential information for verification, integration, and monitoring
# of the deployed infrastructure components

# =============================================================================
# PROJECT AND BASIC INFORMATION
# =============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Primary region for deployed resources"
  value       = var.region
}

output "zone" {
  description = "Primary zone for zonal resources"
  value       = var.zone
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_id.suffix.hex
}

# =============================================================================
# CLOUD COMPOSER OUTPUTS
# =============================================================================

output "composer_environment_name" {
  description = "Name of the Cloud Composer environment"
  value       = google_composer_environment.content_pipeline_composer.name
}

output "composer_environment_uri" {
  description = "URI of the Cloud Composer environment"
  value       = google_composer_environment.content_pipeline_composer.config[0].airflow_uri
}

output "composer_gcs_bucket" {
  description = "GCS bucket used by the Composer environment for DAGs and data"
  value       = google_composer_environment.content_pipeline_composer.config[0].dag_gcs_prefix
}

output "composer_gke_cluster" {
  description = "GKE cluster name used by the Composer environment"
  value       = google_composer_environment.content_pipeline_composer.config[0].gke_cluster
}

output "composer_service_account" {
  description = "Service account email used by the Composer environment"
  value       = google_composer_environment.content_pipeline_composer.config[0].node_config[0].service_account
}

# =============================================================================
# CLOUD STORAGE OUTPUTS
# =============================================================================

output "content_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for content artifacts"
  value       = google_storage_bucket.content_pipeline_bucket.name
}

output "content_storage_bucket_url" {
  description = "GS URL of the content storage bucket"
  value       = google_storage_bucket.content_pipeline_bucket.url
}

output "content_storage_bucket_location" {
  description = "Location of the content storage bucket"
  value       = google_storage_bucket.content_pipeline_bucket.location
}

output "content_storage_bucket_class" {
  description = "Storage class of the content bucket"
  value       = google_storage_bucket.content_pipeline_bucket.storage_class
}

# =============================================================================
# VERTEX AI OUTPUTS
# =============================================================================

output "vertex_ai_dataset_name" {
  description = "Name of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.content_generation_dataset.display_name
}

output "vertex_ai_dataset_id" {
  description = "Full resource ID of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.content_generation_dataset.name
}

output "vertex_ai_featurestore_name" {
  description = "Name of the Vertex AI Featurestore"
  value       = google_vertex_ai_featurestore.content_features.name
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = google_vertex_ai_dataset.content_generation_dataset.region
}

# =============================================================================
# CLOUD RUN OUTPUTS
# =============================================================================

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service hosting the content API"
  value       = google_cloud_run_service.content_api.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service for API access"
  value       = google_cloud_run_service.content_api.status[0].url
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_service.content_api.location
}

output "cloud_run_latest_revision" {
  description = "Latest revision name of the Cloud Run service"
  value       = google_cloud_run_service.content_api.status[0].latest_ready_revision_name
}

# =============================================================================
# NETWORKING OUTPUTS
# =============================================================================

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.content_pipeline_vpc.name
}

output "vpc_network_id" {
  description = "Full resource ID of the VPC network"
  value       = google_compute_network.content_pipeline_vpc.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.content_pipeline_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.content_pipeline_subnet.ip_cidr_range
}

output "subnet_id" {
  description = "Full resource ID of the subnet"
  value       = google_compute_subnetwork.content_pipeline_subnet.id
}

# =============================================================================
# IAM AND SECURITY OUTPUTS
# =============================================================================

output "service_account_email" {
  description = "Email address of the content pipeline service account"
  value       = google_service_account.content_pipeline_sa.email
}

output "service_account_id" {
  description = "Full resource ID of the service account"
  value       = google_service_account.content_pipeline_sa.id
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.content_pipeline_sa.unique_id
}

# =============================================================================
# MONITORING AND LOGGING OUTPUTS
# =============================================================================

output "log_sink_name" {
  description = "Name of the logging sink (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.content_pipeline_sink[0].name : null
}

output "log_sink_destination" {
  description = "Destination of the logging sink (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.content_pipeline_sink[0].destination : null
}

output "budget_name" {
  description = "Name of the billing budget (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_billing_budget.content_pipeline_budget[0].display_name : null
}

# =============================================================================
# API ENDPOINTS AND INTEGRATION
# =============================================================================

output "content_generation_api_endpoint" {
  description = "Full URL for the content generation API endpoint"
  value       = "${google_cloud_run_service.content_api.status[0].url}/generate-content"
}

output "content_status_api_endpoint" {
  description = "Base URL for the content status API endpoint"
  value       = "${google_cloud_run_service.content_api.status[0].url}/content-status"
}

output "health_check_endpoint" {
  description = "Health check endpoint for the content API"
  value       = "${google_cloud_run_service.content_api.status[0].url}/health"
}

# =============================================================================
# CONFIGURATION VALUES FOR EXTERNAL INTEGRATION
# =============================================================================

output "deployment_configuration" {
  description = "Key configuration values for external systems integration"
  value = {
    project_id                = var.project_id
    region                   = var.region
    composer_environment     = google_composer_environment.content_pipeline_composer.name
    composer_airflow_uri     = google_composer_environment.content_pipeline_composer.config[0].airflow_uri
    content_storage_bucket   = google_storage_bucket.content_pipeline_bucket.name
    cloud_run_service_url    = google_cloud_run_service.content_api.status[0].url
    service_account_email    = google_service_account.content_pipeline_sa.email
    vertex_ai_dataset_name   = google_vertex_ai_dataset.content_generation_dataset.display_name
    vpc_network_name         = google_compute_network.content_pipeline_vpc.name
    subnet_name              = google_compute_subnetwork.content_pipeline_subnet.name
  }
  sensitive = false
}

# =============================================================================
# ENVIRONMENT-SPECIFIC OUTPUTS
# =============================================================================

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was last applied"
  value       = timestamp()
}

# =============================================================================
# COST AND RESOURCE INFORMATION
# =============================================================================

output "estimated_monthly_cost_info" {
  description = "Information about potential monthly costs (estimates)"
  value = {
    cloud_composer_nodes     = "${var.composer_node_count} x ${var.composer_machine_type}"
    cloud_run_config        = "${var.cloud_run_cpu} CPU, ${var.cloud_run_memory} memory"
    storage_class           = var.storage_class
    budget_limit_usd        = var.budget_amount
    environment             = var.environment
    cost_optimization_note  = "Actual costs depend on usage. Monitor via Cloud Billing."
  }
}

# =============================================================================
# QUICK START COMMANDS
# =============================================================================

output "quick_start_commands" {
  description = "Useful commands for getting started with the deployed infrastructure"
  value = {
    access_composer_ui = "Open ${google_composer_environment.content_pipeline_composer.config[0].airflow_uri} in your browser"
    test_api_health   = "curl ${google_cloud_run_service.content_api.status[0].url}/health"
    view_storage      = "gsutil ls gs://${google_storage_bucket.content_pipeline_bucket.name}"
    trigger_content   = "curl -X POST ${google_cloud_run_service.content_api.status[0].url}/generate-content -H 'Content-Type: application/json' -d '{\"target_audience\":\"test\",\"content_type\":\"blog\",\"brand_guidelines\":{\"tone\":\"professional\"}}'"
    check_logs       = "gcloud logging read 'resource.type=\"cloud_run_revision\" OR resource.type=\"composer_environment\"' --limit=50 --project=${var.project_id}"
  }
}

# =============================================================================
# SECURITY AND COMPLIANCE INFORMATION
# =============================================================================

output "security_configuration" {
  description = "Security and compliance configuration details"
  value = {
    private_composer_environment = "true"
    storage_uniform_access      = "true"
    storage_versioning_enabled  = tostring(var.enable_versioning)
    deletion_protection_enabled = tostring(var.deletion_protection)
    audit_logging_enabled       = tostring(var.enable_audit_logging)
    vpc_native_networking       = "true"
    service_account_principle   = "Least privilege IAM roles applied"
  }
}

# =============================================================================
# TROUBLESHOOTING INFORMATION
# =============================================================================

output "troubleshooting_info" {
  description = "Helpful information for troubleshooting common issues"
  value = {
    composer_logs_command    = "gcloud composer environments describe ${google_composer_environment.content_pipeline_composer.name} --location=${var.region} --project=${var.project_id}"
    cloud_run_logs_command   = "gcloud run services logs read ${google_cloud_run_service.content_api.name} --region=${var.region} --project=${var.project_id}"
    storage_permissions_info = "Ensure the service account ${google_service_account.content_pipeline_sa.email} has access to the bucket"
    vertex_ai_quota_info     = "Check Vertex AI quotas if experiencing API limits"
    network_connectivity    = "Verify firewall rules allow necessary traffic"
  }
}