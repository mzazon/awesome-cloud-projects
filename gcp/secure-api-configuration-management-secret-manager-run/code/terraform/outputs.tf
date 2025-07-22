# Output values for the secure API configuration management infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "cloud_run_service_name" {
  description = "Name of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.secure_api.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service for direct access"
  value       = google_cloud_run_v2_service.secure_api.uri
  sensitive   = false
}

output "cloud_run_service_id" {
  description = "Full resource ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.secure_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway"
  value       = google_api_gateway_gateway.secure_api_gateway.gateway_id
}

output "api_gateway_url" {
  description = "URL of the API Gateway for managed access"
  value       = "https://${google_api_gateway_gateway.secure_api_gateway.default_hostname}"
  sensitive   = false
}

output "api_gateway_id" {
  description = "Full resource ID of the API Gateway"
  value       = google_api_gateway_gateway.secure_api_gateway.id
}

output "service_account_email" {
  description = "Email address of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_sa.email
}

output "service_account_id" {
  description = "Full resource ID of the service account"
  value       = google_service_account.cloud_run_sa.id
}

output "secret_names" {
  description = "Names of the created Secret Manager secrets"
  value = {
    database    = google_secret_manager_secret.api_secrets["database"].secret_id
    api_keys    = google_secret_manager_secret.api_secrets["api_keys"].secret_id
    application = google_secret_manager_secret.api_secrets["application"].secret_id
  }
}

output "secret_ids" {
  description = "Full resource IDs of the Secret Manager secrets"
  value = {
    database    = google_secret_manager_secret.api_secrets["database"].id
    api_keys    = google_secret_manager_secret.api_secrets["api_keys"].id
    application = google_secret_manager_secret.api_secrets["application"].id
  }
  sensitive = true
}

output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing application source"
  value       = google_storage_bucket.source_bucket.name
}

output "source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing application source"
  value       = google_storage_bucket.source_bucket.url
}

output "audit_logs_bucket_name" {
  description = "Name of the audit logs storage bucket (if enabled)"
  value       = var.enable_audit_logs ? google_storage_bucket.audit_logs[0].name : null
}

output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.secret_access_anomaly[0].id : null
}

output "logging_sink_id" {
  description = "ID of the audit logging sink (if enabled)"
  value       = var.enable_audit_logs ? google_logging_project_sink.secret_audit_sink[0].id : null
}

output "enabled_apis" {
  description = "List of APIs that were enabled for this deployment"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Security-related outputs
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account_email     = google_service_account.cloud_run_sa.email
    deletion_protection      = var.deletion_protection
    ingress_traffic         = var.ingress_traffic
    secret_rotation_enabled = var.enable_secret_rotation
    monitoring_enabled      = var.enable_monitoring
    audit_logs_enabled      = var.enable_audit_logs
    vpc_connector_enabled   = var.enable_vpc_connector
  }
}

# Connection information for testing and integration
output "service_endpoints" {
  description = "Available service endpoints for testing"
  value = {
    health_check    = "${google_cloud_run_v2_service.secure_api.uri}/health"
    api_config     = "${google_cloud_run_v2_service.secure_api.uri}/config"
    database_status = "${google_cloud_run_v2_service.secure_api.uri}/database/status"
    secure_data    = "${google_cloud_run_v2_service.secure_api.uri}/api/data"
  }
}

# Gateway endpoints with proper formatting
output "gateway_endpoints" {
  description = "API Gateway endpoints for managed access"
  value = {
    base_url        = "https://${google_api_gateway_gateway.secure_api_gateway.default_hostname}"
    health_check    = "https://${google_api_gateway_gateway.secure_api_gateway.default_hostname}/health"
    api_config     = "https://${google_api_gateway_gateway.secure_api_gateway.default_hostname}/config"
    database_status = "https://${google_api_gateway_gateway.secure_api_gateway.default_hostname}/database/status"
    secure_data    = "https://${google_api_gateway_gateway.secure_api_gateway.default_hostname}/api/data"
  }
}

# Resource naming information
output "resource_naming" {
  description = "Naming convention and suffixes used for resources"
  value = {
    resource_suffix = local.resource_suffix
    service_name    = local.service_name
    gateway_name    = local.gateway_name
    environment     = var.environment
  }
}

# Scaling configuration output
output "scaling_configuration" {
  description = "Current scaling configuration for the Cloud Run service"
  value = {
    min_instances = var.scaling_config.min_instances
    max_instances = var.scaling_config.max_instances
    cpu          = var.container_resources.cpu
    memory       = var.container_resources.memory
  }
}

# Labels applied to resources
output "applied_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}