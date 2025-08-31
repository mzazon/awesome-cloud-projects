# ============================================================================
# API Schema Generation with Gemini Code Assist and Cloud Build - Outputs
# ============================================================================
# This file defines output values that provide important information about
# the created resources for integration and verification purposes.

# ============================================================================
# Project and Environment Information
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name used for resource labeling"
  value       = var.environment
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

# ============================================================================
# Cloud Storage Outputs
# ============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for API schemas and artifacts"
  value       = google_storage_bucket.api_schemas.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.api_schemas.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket for API references"
  value       = google_storage_bucket.api_schemas.self_link
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.api_schemas.location
}

output "docs_folder_path" {
  description = "Cloud Storage path for documentation artifacts"
  value       = "gs://${google_storage_bucket.api_schemas.name}/docs/"
}

output "reports_folder_path" {
  description = "Cloud Storage path for build reports"
  value       = "gs://${google_storage_bucket.api_schemas.name}/reports/"
}

output "schemas_folder_path" {
  description = "Cloud Storage path for generated schemas"
  value       = "gs://${google_storage_bucket.api_schemas.name}/schemas/"
}

# ============================================================================
# Cloud Functions Outputs
# ============================================================================

output "schema_generator_function_name" {
  description = "Name of the schema generator Cloud Function"
  value       = google_cloudfunctions_function.schema_generator.name
}

output "schema_generator_function_url" {
  description = "HTTPS trigger URL for the schema generator function"
  value       = google_cloudfunctions_function.schema_generator.https_trigger_url
  sensitive   = false
}

output "schema_generator_function_region" {
  description = "Region where the schema generator function is deployed"
  value       = google_cloudfunctions_function.schema_generator.region
}

output "schema_generator_function_runtime" {
  description = "Runtime version of the schema generator function"
  value       = google_cloudfunctions_function.schema_generator.runtime
}

output "schema_validator_function_name" {
  description = "Name of the schema validator Cloud Function"
  value       = google_cloudfunctions_function.schema_validator.name
}

output "schema_validator_function_url" {
  description = "HTTPS trigger URL for the schema validator function"
  value       = google_cloudfunctions_function.schema_validator.https_trigger_url
  sensitive   = false
}

output "schema_validator_function_region" {
  description = "Region where the schema validator function is deployed"
  value       = google_cloudfunctions_function.schema_validator.region
}

output "schema_validator_function_runtime" {
  description = "Runtime version of the schema validator function"
  value       = google_cloudfunctions_function.schema_validator.runtime
}

# ============================================================================
# Service Account Outputs
# ============================================================================

output "cloud_functions_service_account_email" {
  description = "Email address of the Cloud Functions service account"
  value       = google_service_account.cloud_functions_sa.email
}

output "cloud_functions_service_account_id" {
  description = "ID of the Cloud Functions service account"
  value       = google_service_account.cloud_functions_sa.account_id
}

output "cloud_build_service_account_email" {
  description = "Email address of the Cloud Build service account"
  value       = google_service_account.cloud_build_sa.email
}

output "cloud_build_service_account_id" {
  description = "ID of the Cloud Build service account"
  value       = google_service_account.cloud_build_sa.account_id
}

# ============================================================================
# Cloud Build Outputs
# ============================================================================

output "build_trigger_name" {
  description = "Name of the Cloud Build trigger for the API schema pipeline"
  value       = google_cloudbuild_trigger.api_schema_pipeline.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.api_schema_pipeline.trigger_id
}

output "build_trigger_description" {
  description = "Description of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.api_schema_pipeline.description
}

output "build_manual_trigger_command" {
  description = "Command to manually trigger the build pipeline"
  value = "gcloud builds submit --config=cloudbuild.yaml --substitutions=_BUCKET_NAME=${google_storage_bucket.api_schemas.name},_FUNCTION_URL=${google_cloudfunctions_function.schema_generator.https_trigger_url}"
}

# ============================================================================
# Monitoring and Logging Outputs
# ============================================================================

output "function_log_sink_name" {
  description = "Name of the log sink for Cloud Functions"
  value       = google_logging_project_sink.function_logs.name
}

output "build_log_sink_name" {
  description = "Name of the log sink for Cloud Build"
  value       = google_logging_project_sink.build_logs.name
}

output "monitoring_notification_channel_ids" {
  description = "IDs of monitoring notification channels"
  value = var.notification_email != null ? [
    google_monitoring_notification_channel.email[0].id
  ] : []
}

output "function_errors_alert_policy_name" {
  description = "Name of the alert policy for function errors"
  value       = google_monitoring_alert_policy.function_errors.display_name
}

output "build_failures_alert_policy_name" {
  description = "Name of the alert policy for build failures"
  value       = google_monitoring_alert_policy.build_failures.display_name
}

# ============================================================================
# API and Service Endpoints
# ============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    google_project_service.cloudbuild.service,
    google_project_service.storage.service,
    google_project_service.cloudfunctions.service,
    google_project_service.artifactregistry.service,
    google_project_service.logging.service,
    google_project_service.monitoring.service,
    google_project_service.iam.service
  ]
}

output "cloud_console_links" {
  description = "Links to Google Cloud Console for key resources"
  value = {
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.api_schemas.name}"
    cloud_functions = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    cloud_build = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
    monitoring = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logs = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# ============================================================================
# Configuration and Usage Information
# ============================================================================

output "function_invocation_examples" {
  description = "Example commands for invoking the deployed functions"
  value = {
    schema_generator = {
      curl_command = "curl -X POST '${google_cloudfunctions_function.schema_generator.https_trigger_url}' -H 'Content-Type: application/json' -d '{}'"
      gcloud_command = "gcloud functions call ${google_cloudfunctions_function.schema_generator.name} --region=${var.region}"
    }
    schema_validator = {
      curl_command = "curl -X POST '${google_cloudfunctions_function.schema_validator.https_trigger_url}' -H 'Content-Type: application/json' -d '{\"bucket_name\": \"${google_storage_bucket.api_schemas.name}\"}'"
      gcloud_command = "gcloud functions call ${google_cloudfunctions_function.schema_validator.name} --region=${var.region} --data='{\"bucket_name\": \"${google_storage_bucket.api_schemas.name}\"}'"
    }
  }
}

output "storage_access_commands" {
  description = "Commands for accessing stored artifacts"
  value = {
    list_schemas = "gsutil ls gs://${google_storage_bucket.api_schemas.name}/docs/"
    list_reports = "gsutil ls gs://${google_storage_bucket.api_schemas.name}/reports/"
    download_latest_schema = "gsutil cp gs://${google_storage_bucket.api_schemas.name}/docs/openapi-schema.json ./"
    view_bucket_contents = "gsutil ls -r gs://${google_storage_bucket.api_schemas.name}/"
  }
}

output "monitoring_commands" {
  description = "Commands for monitoring and observability"
  value = {
    view_function_logs = "gcloud logs read 'resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.schema_generator.name}\"' --project=${var.project_id} --limit=50"
    view_build_logs = "gcloud logs read 'resource.type=\"build\"' --project=${var.project_id} --limit=20"
    list_builds = "gcloud builds list --project=${var.project_id} --limit=10"
    trigger_build = "gcloud builds triggers run ${google_cloudbuild_trigger.api_schema_pipeline.name} --project=${var.project_id} --branch=main"
  }
}

# ============================================================================
# Resource Costs and Limits
# ============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (in USD, approximate)"
  value = {
    cloud_storage = "~$0.02-0.10 (depending on storage usage)"
    cloud_functions = "~$0.00-2.00 (depending on invocations)"
    cloud_build = "~$0.00-10.00 (depending on build minutes)"
    logging = "~$0.50-2.00 (depending on log volume)"
    monitoring = "~$0.15-1.00 (depending on metrics volume)"
    total_estimated = "~$0.67-15.10 per month"
    note = "Costs depend on actual usage. Monitor billing for accurate costs."
  }
}

output "resource_quotas_and_limits" {
  description = "Important quotas and limits for the deployed resources"
  value = {
    cloud_functions = {
      max_instances = var.function_max_instances
      timeout_seconds = var.function_timeout_seconds
      memory_mb = var.function_memory_mb
    }
    cloud_build = {
      timeout_seconds = var.build_timeout_seconds
      machine_type = var.build_machine_type
      disk_size_gb = var.build_disk_size_gb
    }
    storage = {
      retention_days = var.retention_period_days
      storage_class = var.storage_class
    }
  }
}

# ============================================================================
# Security and Access Information
# ============================================================================

output "iam_roles_assigned" {
  description = "IAM roles assigned to service accounts"
  value = {
    cloud_functions_sa = [
      "roles/storage.objectAdmin",
      "roles/logging.logWriter"
    ]
    cloud_build_sa = [
      "roles/storage.admin",
      "roles/logging.logWriter",
      "roles/cloudfunctions.invoker"
    ]
  }
}

output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    recommendations = [
      "Review and restrict Cloud Function trigger access if needed",
      "Monitor service account usage and permissions regularly",
      "Enable Cloud Security Command Center for additional security insights",
      "Implement VPC Service Controls for sensitive workloads",
      "Regularly rotate service account keys if using key-based authentication",
      "Review and update IAM bindings based on principle of least privilege"
    ]
    security_contacts = var.notification_email != null ? [var.notification_email] : []
  }
}

# ============================================================================
# Integration and Development Information
# ============================================================================

output "integration_endpoints" {
  description = "Endpoints and URIs for integration with other systems"
  value = {
    schema_generation_webhook = google_cloudfunctions_function.schema_generator.https_trigger_url
    schema_validation_webhook = google_cloudfunctions_function.schema_validator.https_trigger_url
    artifact_storage_uri = "gs://${google_storage_bucket.api_schemas.name}"
    build_trigger_webhook = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/triggers/${google_cloudbuild_trigger.api_schema_pipeline.trigger_id}:webhook"
  }
}

output "development_setup" {
  description = "Information for developers to work with this infrastructure"
  value = {
    clone_repository = "git clone https://github.com/${var.repository_owner}/${var.repository_name}.git"
    local_testing = {
      functions_framework = "functions-framework --target=generate_schema --source=function-sources/schema-generator"
      schema_validation = "python function-sources/schema-validator/main.py"
    }
    environment_variables = {
      PROJECT_ID = var.project_id
      BUCKET_NAME = google_storage_bucket.api_schemas.name
      REGION = var.region
      FUNCTION_URL = google_cloudfunctions_function.schema_generator.https_trigger_url
    }
  }
}

# ============================================================================
# Troubleshooting and Support Information
# ============================================================================

output "troubleshooting_guide" {
  description = "Common troubleshooting commands and information"
  value = {
    check_function_status = "gcloud functions describe ${google_cloudfunctions_function.schema_generator.name} --region=${var.region}"
    check_build_history = "gcloud builds list --filter='trigger_id=${google_cloudbuild_trigger.api_schema_pipeline.trigger_id}' --limit=5"
    check_storage_permissions = "gsutil iam get gs://${google_storage_bucket.api_schemas.name}"
    debug_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.schema_generator.name} --region=${var.region} --limit=50"
    test_connectivity = "curl -I ${google_cloudfunctions_function.schema_generator.https_trigger_url}"
  }
}

output "support_information" {
  description = "Support and contact information for this deployment"
  value = {
    terraform_version = "~> 1.0"
    google_provider_version = "~> 5.0"
    deployment_date = timestamp()
    maintainer = var.owner != "" ? var.owner : "DevOps Team"
    cost_center = var.cost_center != "" ? var.cost_center : "Not specified"
    project_code = var.project_code != "" ? var.project_code : "Not specified"
    documentation_links = [
      "https://cloud.google.com/functions/docs",
      "https://cloud.google.com/build/docs",
      "https://cloud.google.com/storage/docs",
      "https://cloud.google.com/monitoring/docs"
    ]
  }
}

# ============================================================================
# Resource Identifiers for External References
# ============================================================================

output "resource_ids" {
  description = "Resource IDs for external references and automation"
  value = {
    storage_bucket_id = google_storage_bucket.api_schemas.id
    schema_generator_function_id = google_cloudfunctions_function.schema_generator.id
    schema_validator_function_id = google_cloudfunctions_function.schema_validator.id
    build_trigger_id = google_cloudbuild_trigger.api_schema_pipeline.id
    cloud_functions_sa_id = google_service_account.cloud_functions_sa.id
    cloud_build_sa_id = google_service_account.cloud_build_sa.id
    function_log_sink_id = google_logging_project_sink.function_logs.id
    build_log_sink_id = google_logging_project_sink.build_logs.id
  }
}

# ============================================================================
# Configuration Summary
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure configuration"
  value = {
    infrastructure_type = "API Schema Generation Pipeline"
    cloud_provider = "Google Cloud Platform"
    region = var.region
    environment = var.environment
    components_deployed = [
      "Cloud Storage Bucket",
      "Schema Generator Function",
      "Schema Validator Function", 
      "Cloud Build Trigger",
      "Service Accounts",
      "IAM Bindings",
      "Logging Sinks",
      "Monitoring Alerts"
    ]
    estimated_setup_time = "5-10 minutes"
    estimated_monthly_cost = "$0.67-15.10 USD"
    security_level = "Production-ready with least privilege access"
    monitoring_enabled = var.enable_monitoring
    alerting_configured = var.notification_email != null
  }
}