# Outputs for Secure Package Distribution Workflows
# These outputs provide essential information for integration and verification

# Project and Region Information
output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

# Resource Naming
output "resource_name_prefix" {
  description = "The prefix used for naming all resources"
  value       = "secure-packages-${random_id.suffix.hex}"
}

output "random_suffix" {
  description = "The random suffix used for unique resource names"
  value       = random_id.suffix.hex
}

# Artifact Registry Outputs
output "artifact_registry_repositories" {
  description = "Map of Artifact Registry repositories created"
  value = {
    for format in var.repository_formats : format => {
      name         = module.artifact_registry_repositories[format].artifact_name
      id           = module.artifact_registry_repositories[format].artifact_id
      create_time  = module.artifact_registry_repositories[format].create_time
      update_time  = module.artifact_registry_repositories[format].update_time
      url          = "https://${var.region}-docker.pkg.dev/${var.project_id}/secure-packages-${random_id.suffix.hex}-${format}"
    }
  }
}

output "docker_registry_url" {
  description = "URL for the Docker registry (if Docker repository is enabled)"
  value = contains(var.repository_formats, "docker") ? 
    "https://${var.region}-docker.pkg.dev/${var.project_id}/secure-packages-${random_id.suffix.hex}-docker" : 
    null
}

output "npm_registry_url" {
  description = "URL for the NPM registry (if NPM repository is enabled)"
  value = contains(var.repository_formats, "npm") ? 
    "https://${var.region}-npm.pkg.dev/${var.project_id}/secure-packages-${random_id.suffix.hex}-npm" : 
    null
}

output "maven_registry_url" {
  description = "URL for the Maven registry (if Maven repository is enabled)"
  value = contains(var.repository_formats, "maven") ? 
    "https://${var.region}-maven.pkg.dev/${var.project_id}/secure-packages-${random_id.suffix.hex}-maven" : 
    null
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the package distribution service account"
  value       = google_service_account.package_distributor.email
}

output "service_account_name" {
  description = "Name of the package distribution service account"
  value       = google_service_account.package_distributor.name
}

output "service_account_id" {
  description = "ID of the package distribution service account"
  value       = google_service_account.package_distributor.account_id
}

# Secret Manager Outputs
output "secret_manager_secrets" {
  description = "Map of Secret Manager secrets created"
  value = {
    for env in local.environments : env => {
      name = google_secret_manager_secret.registry_credentials[env].name
      id   = google_secret_manager_secret.registry_credentials[env].secret_id
    }
  }
}

output "distribution_config_secret" {
  description = "Information about the distribution configuration secret"
  value = {
    name = google_secret_manager_secret.distribution_config.name
    id   = google_secret_manager_secret.distribution_config.secret_id
  }
}

# Cloud Function Outputs
output "cloud_function_name" {
  description = "Name of the package distribution Cloud Function"
  value       = google_cloudfunctions_function.package_distributor.name
}

output "cloud_function_url" {
  description = "HTTPS trigger URL for the package distribution Cloud Function"
  value       = google_cloudfunctions_function.package_distributor.https_trigger_url
}

output "cloud_function_source_bucket" {
  description = "Cloud Storage bucket containing the function source code"
  value       = google_storage_bucket.function_source.name
}

# Cloud Tasks Outputs
output "cloud_tasks_queues" {
  description = "Information about Cloud Tasks queues"
  value = {
    standard_queue = {
      name = google_cloud_tasks_queue.package_distribution.name
      id   = google_cloud_tasks_queue.package_distribution.id
    }
    production_queue = {
      name = google_cloud_tasks_queue.prod_distribution.name
      id   = google_cloud_tasks_queue.prod_distribution.id
    }
  }
}

# Cloud Scheduler Outputs
output "cloud_scheduler_jobs" {
  description = "Information about Cloud Scheduler jobs"
  value = {
    nightly_job = {
      name     = google_cloud_scheduler_job.nightly_distribution.name
      id       = google_cloud_scheduler_job.nightly_distribution.id
      schedule = google_cloud_scheduler_job.nightly_distribution.schedule
    }
    weekly_staging_job = {
      name     = google_cloud_scheduler_job.weekly_staging.name
      id       = google_cloud_scheduler_job.weekly_staging.id
      schedule = google_cloud_scheduler_job.weekly_staging.schedule
    }
    production_job = {
      name     = google_cloud_scheduler_job.prod_manual.name
      id       = google_cloud_scheduler_job.prod_manual.id
      schedule = google_cloud_scheduler_job.prod_manual.schedule
    }
  }
}

# KMS Outputs
output "kms_key_ring" {
  description = "Information about the KMS key ring"
  value = {
    name = google_kms_key_ring.package_distribution.name
    id   = google_kms_key_ring.package_distribution.id
  }
}

output "kms_crypto_keys" {
  description = "Information about KMS crypto keys"
  value = {
    artifact_registry_key = {
      name = google_kms_crypto_key.artifact_registry.name
      id   = google_kms_crypto_key.artifact_registry.id
    }
    secret_manager_key = {
      name = google_kms_crypto_key.secret_manager.name
      id   = google_kms_crypto_key.secret_manager.id
    }
  }
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "log_based_metrics" {
  description = "Information about log-based metrics (if monitoring is enabled)"
  value = var.enable_monitoring ? {
    distribution_failures = {
      name = google_logging_metric.distribution_failures[0].name
      id   = google_logging_metric.distribution_failures[0].id
    }
    distribution_success = {
      name = google_logging_metric.distribution_success[0].name
      id   = google_logging_metric.distribution_success[0].id
    }
  } : null
}

output "alert_policy" {
  description = "Information about the alert policy (if monitoring is enabled)"
  value = var.enable_monitoring ? {
    name = google_monitoring_alert_policy.distribution_failures[0].name
    id   = google_monitoring_alert_policy.distribution_failures[0].id
  } : null
}

# Audit Logging Outputs
output "audit_logging_enabled" {
  description = "Whether audit logging is enabled"
  value       = var.enable_audit_logging
}

output "audit_log_bucket" {
  description = "Cloud Storage bucket for audit logs (if audit logging is enabled)"
  value = var.enable_audit_logging ? {
    name = google_storage_bucket.audit_logs[0].name
    id   = google_storage_bucket.audit_logs[0].id
    url  = google_storage_bucket.audit_logs[0].url
  } : null
}

# Security Configuration Outputs
output "security_configuration" {
  description = "Summary of security configuration applied"
  value = {
    kms_encryption_enabled       = true
    iam_least_privilege         = true
    secret_rotation_enabled     = true
    vulnerability_scanning      = var.enable_vulnerability_scanning
    audit_logging_enabled       = var.enable_audit_logging
    https_only_functions        = true
    uniform_bucket_level_access = true
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Key endpoints for integration with other systems"
  value = {
    package_distribution_webhook = google_cloudfunctions_function.package_distributor.https_trigger_url
    docker_registry_endpoint     = contains(var.repository_formats, "docker") ? "${var.region}-docker.pkg.dev" : null
    npm_registry_endpoint        = contains(var.repository_formats, "npm") ? "${var.region}-npm.pkg.dev" : null
    maven_registry_endpoint      = contains(var.repository_formats, "maven") ? "${var.region}-maven.pkg.dev" : null
  }
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    total_repositories_created = length(var.repository_formats)
    total_secrets_created      = length(local.environments) + 1  # +1 for config secret
    total_functions_deployed   = 1
    total_queues_created       = 2
    total_scheduler_jobs       = 3
    monitoring_enabled         = var.enable_monitoring
    audit_logging_enabled      = var.enable_audit_logging
    kms_keys_created          = 2
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Basic usage instructions for the deployed infrastructure"
  value = {
    authenticate_docker = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    test_function = "curl -X POST '${google_cloudfunctions_function.package_distributor.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"package_name\":\"test\",\"package_version\":\"1.0.0\",\"environment\":\"dev\"}'"
    view_logs = "gcloud functions logs read ${google_cloudfunctions_function.package_distributor.name} --region=${var.region}"
    manual_trigger_scheduler = "gcloud scheduler jobs run ${google_cloud_scheduler_job.nightly_distribution.name} --location=${var.region}"
  }
}