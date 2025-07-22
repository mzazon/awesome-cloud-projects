# Project and Configuration Outputs
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "service_prefix" {
  description = "Service prefix used for resource naming"
  value       = local.service_prefix
}

# Cloud Storage Bucket Outputs
output "input_bucket_name" {
  description = "Name of the input data bucket"
  value       = google_storage_bucket.input_bucket.name
}

output "input_bucket_url" {
  description = "URL of the input data bucket"
  value       = google_storage_bucket.input_bucket.url
}

output "model_bucket_name" {
  description = "Name of the model storage bucket"
  value       = google_storage_bucket.model_bucket.name
}

output "model_bucket_url" {
  description = "URL of the model storage bucket"
  value       = google_storage_bucket.model_bucket.url
}

output "output_bucket_name" {
  description = "Name of the output results bucket"
  value       = google_storage_bucket.output_bucket.name
}

output "output_bucket_url" {
  description = "URL of the output results bucket"
  value       = google_storage_bucket.output_bucket.url
}

# Cloud Run Service Outputs
output "gpu_inference_service_name" {
  description = "Name of the GPU inference Cloud Run service"
  value       = google_cloud_run_v2_service.gpu_inference_service.name
}

output "gpu_inference_service_url" {
  description = "URL of the GPU inference Cloud Run service"
  value       = google_cloud_run_v2_service.gpu_inference_service.uri
}

output "preprocess_service_name" {
  description = "Name of the preprocessing Cloud Run service"
  value       = google_cloud_run_v2_service.preprocess_service.name
}

output "preprocess_service_url" {
  description = "URL of the preprocessing Cloud Run service"
  value       = google_cloud_run_v2_service.preprocess_service.uri
}

output "postprocess_service_name" {
  description = "Name of the postprocessing Cloud Run service"
  value       = google_cloud_run_v2_service.postprocess_service.name
}

output "postprocess_service_url" {
  description = "URL of the postprocessing Cloud Run service"
  value       = google_cloud_run_v2_service.postprocess_service.uri
}

# Cloud Run Service Configuration Outputs
output "gpu_service_config" {
  description = "Configuration details for GPU inference service"
  value = {
    memory_gb       = var.gpu_service_config.memory_gb
    cpu_count       = var.gpu_service_config.cpu_count
    gpu_count       = var.gpu_service_config.gpu_count
    gpu_type        = var.gpu_service_config.gpu_type
    timeout_seconds = var.gpu_service_config.timeout_seconds
    concurrency     = var.gpu_service_config.concurrency
    max_instances   = var.gpu_service_config.max_instances
  }
}

# Workflow Outputs
output "workflow_name" {
  description = "Name of the Cloud Workflows ML pipeline"
  value       = google_workflows_workflow.ml_pipeline.name
}

output "workflow_id" {
  description = "ID of the Cloud Workflows ML pipeline"
  value       = google_workflows_workflow.ml_pipeline.id
}

output "workflow_state" {
  description = "Current state of the workflow"
  value       = google_workflows_workflow.ml_pipeline.state
}

# Eventarc Trigger Outputs
output "eventarc_trigger_name" {
  description = "Name of the Eventarc trigger for storage events"
  value       = google_eventarc_trigger.storage_trigger.name
}

output "eventarc_trigger_uid" {
  description = "UID of the Eventarc trigger"
  value       = google_eventarc_trigger.storage_trigger.uid
}

# Service Account Outputs
output "eventarc_service_account_email" {
  description = "Email of the Eventarc service account"
  value       = google_service_account.eventarc_sa.email
}

output "workflow_service_account_email" {
  description = "Email of the Workflow service account"
  value       = google_service_account.workflow_sa.email
}

# Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_registry.name
}

output "container_registry_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${google_artifact_registry_repository.container_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}"
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL of the Cloud Monitoring dashboard (if enabled)"
  value       = var.monitoring_config.enable_cloud_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.ml_pipeline_dashboard[0].id}?project=${var.project_id}" : null
}

output "log_sink_name" {
  description = "Name of the log sink for pipeline logs (if enabled)"
  value       = var.monitoring_config.enable_cloud_monitoring ? google_logging_project_sink.ml_pipeline_logs[0].name : null
}

# API Status Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = keys(google_project_service.required_apis)
}

# Pipeline Endpoint URLs for Testing
output "pipeline_endpoints" {
  description = "All pipeline service endpoints for testing"
  value = {
    gpu_inference_health = "${google_cloud_run_v2_service.gpu_inference_service.uri}/health"
    gpu_inference_predict = "${google_cloud_run_v2_service.gpu_inference_service.uri}/predict"
    preprocess_health    = "${google_cloud_run_v2_service.preprocess_service.uri}/health"
    preprocess_endpoint  = "${google_cloud_run_v2_service.preprocess_service.uri}/preprocess"
    postprocess_health   = "${google_cloud_run_v2_service.postprocess_service.uri}/health"
    postprocess_endpoint = "${google_cloud_run_v2_service.postprocess_service.uri}/postprocess"
  }
}

# Workflow Execution Commands
output "workflow_execution_commands" {
  description = "Commands for executing and monitoring the workflow"
  value = {
    execute_workflow = "gcloud workflows execute ${google_workflows_workflow.ml_pipeline.name} --location=${var.region} --data='{\"input_file\":\"your-test-file.txt\"}'"
    list_executions  = "gcloud workflows executions list --workflow=${google_workflows_workflow.ml_pipeline.name} --location=${var.region}"
    describe_workflow = "gcloud workflows describe ${google_workflows_workflow.ml_pipeline.name} --location=${var.region}"
  }
}

# Testing Commands
output "testing_commands" {
  description = "Commands for testing the ML pipeline"
  value = {
    upload_test_file = "echo 'This is a test message for sentiment analysis' > test-input.txt && gsutil cp test-input.txt gs://${google_storage_bucket.input_bucket.name}/"
    check_output     = "gsutil ls gs://${google_storage_bucket.output_bucket.name}/"
    test_gpu_service = "curl -X GET ${google_cloud_run_v2_service.gpu_inference_service.uri}/health"
    test_preprocess  = "curl -X POST ${google_cloud_run_v2_service.preprocess_service.uri}/health"
    test_postprocess = "curl -X POST ${google_cloud_run_v2_service.postprocess_service.uri}/health"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Cost estimation information for the deployed resources"
  value = {
    gpu_cost_per_hour = "Approximately $0.233 per GPU hour for NVIDIA L4"
    storage_cost = "Standard storage: $0.020 per GB-month"
    cloud_run_cost = "Pay-per-request pricing with generous free tier"
    workflow_cost = "First 5,000 internal steps per month are free"
    note = "Actual costs depend on usage patterns and may vary"
  }
}

# Security Configuration Output
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    authentication_required = var.security_config.require_authentication
    service_accounts_created = [
      google_service_account.eventarc_sa.email,
      google_service_account.workflow_sa.email
    ]
    iam_roles_granted = [
      "roles/workflows.invoker",
      "roles/eventarc.eventReceiver",
      "roles/run.invoker",
      "roles/storage.objectViewer",
      "roles/logging.logWriter"
    ]
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands for cleaning up resources"
  value = {
    terraform_destroy = "terraform destroy -auto-approve"
    manual_cleanup = [
      "gsutil -m rm -r gs://${google_storage_bucket.input_bucket.name}",
      "gsutil -m rm -r gs://${google_storage_bucket.model_bucket.name}",
      "gsutil -m rm -r gs://${google_storage_bucket.output_bucket.name}",
      "gcloud workflows delete ${google_workflows_workflow.ml_pipeline.name} --location=${var.region} --quiet",
      "gcloud eventarc triggers delete ${google_eventarc_trigger.storage_trigger.name} --location=${var.region} --quiet"
    ]
  }
}